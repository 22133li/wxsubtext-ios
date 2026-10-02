#import "WXSubtextCore.h"
#import "WXSubtextConfig.h"
#import "WXSubtextDesensitizer.h"
#import "WXSubtextNetwork.h"
#import "WXSubtextAnalysis.h"
#import "../Hook/WXSubtextLog.h"
#import "../UI/WXSubtextCardView.h"
#import <objc/runtime.h>

static const NSTimeInterval kCacheTTL = 600; // 完整结果缓存 10 分钟（与 Android 一致）
static const NSInteger kMaxHistoryPerTalker = 100; // 每会话持久化保留 100 条
static const NSTimeInterval kOnlyLatestDebounce = 0.3; // 只分析最新时的防抖（原 0.8s）
static const NSTimeInterval kChatEnterSuppress = 2.0; // 进聊天页 2 秒内只缓冲不自动分析

@interface WXSubtextCore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *buffers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WXSubtextAnalysis *> *cache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *cacheTime;
@property (nonatomic, strong) NSMutableArray<NSDate *> *callTimes;
@property (nonatomic, strong) NSMutableSet<NSString *> *inflight;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *lastIncoming; // talker -> 最新对方文本
@property (nonatomic, weak) WXSubtextCardView *currentCard;
// 卡片跟踪：分析的是哪条消息（用于滚动时跟随、cell 复用时失效）
@property (nonatomic, weak) UIView *trackedAnchor;
@property (nonatomic, weak) UIView *trackedContainer;
@property (nonatomic, copy) NSString *trackedText;
// 聊天记录持久化
@property (nonatomic, assign) BOOL historySaveScheduled;
@property (nonatomic, assign) NSTimeInterval chatEnterTime;
@end

@implementation WXSubtextCore
+ (instancetype)shared {
    static WXSubtextCore *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}
- (instancetype)init {
    if (self = [super init]) {
        _buffers = [NSMutableDictionary dictionary];
        _cache = [NSMutableDictionary dictionary];
        _cacheTime = [NSMutableDictionary dictionary];
        _callTimes = [NSMutableArray array];
        _inflight = [NSMutableSet set];
        _lastIncoming = [NSMutableDictionary dictionary];
        [self loadHistory];
    }
    return self;
}

#pragma mark - 聊天记录持久化（微信沙盒 Documents/wxsubtext_history.plist）

- (NSString *)historyPath {
    static NSString *p = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *doc = dirs.firstObject;
        p = doc ? [doc stringByAppendingPathComponent:@"wxsubtext_history.plist"] : nil;
    });
    return p;
}

- (void)loadHistory {
    @try {
        NSString *p = [self historyPath];
        if (!p) return;
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (![d isKindOfClass:[NSDictionary class]]) return;
        for (NSString *talker in d) {
            NSArray *arr = d[talker];
            if (![arr isKindOfClass:[NSArray class]]) continue;
            NSMutableArray *buf = [NSMutableArray array];
            for (id o in arr) if ([o isKindOfClass:[NSString class]]) [buf addObject:o];
            while (buf.count > kMaxHistoryPerTalker) [buf removeObjectAtIndex:0];
            if (buf.count) self.buffers[talker] = buf;
        }
    } @catch (NSException *e) {}
}

- (void)saveHistory {
    @try {
        NSString *p = [self historyPath];
        if (!p) return;
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (NSString *talker in self.buffers) {
            NSArray *buf = self.buffers[talker];
            if (buf.count) d[talker] = [buf copy];
        }
        [d writeToFile:p atomically:YES];
    } @catch (NSException *e) {}
}

- (void)markHistoryDirty {
    if (self.historySaveScheduled) return;
    self.historySaveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.historySaveScheduled = NO;
        [self saveHistory];
    });
}

#pragma mark - 群聊判定（标题形如 xxx(3) 视为群，默认跳过，与 Android 版一致）
- (BOOL)isGroupTalker:(NSString *)t {
    if (!t.length) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\(\\d+\\)$" options:0 error:nil];
    return [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0;
}

#pragma mark - 主入口
- (void)onMessageText:(NSString *)text isFromOther:(BOOL)fromOther
               talker:(NSString *)talker anchorView:(UIView *)anchorView container:(UIView *)container {
    if (!text.length || !talker.length || !container) return;
    if ([self isGroupTalker:talker]) return;
    WXSubtextConfig *cfg = [WXSubtextConfig shared];
    if (![cfg shouldAnalyzeTalker:talker]) return;

    // 维护上下文缓冲（持久化，每会话保留最近 100 条）
    NSMutableArray *buf = self.buffers[talker];
    if (!buf) { buf = [NSMutableArray array]; self.buffers[talker] = buf; }
    NSString *line = [NSString stringWithFormat:@"%@：%@", fromOther ? @"对方" : @"我", text];
    if (![buf.lastObject isEqualToString:line]) {
        [buf addObject:line];
        while (buf.count > kMaxHistoryPerTalker) [buf removeObjectAtIndex:0];
        [self markHistoryDirty];
    }
    if (!fromOther) return; // 只分析对方发来的消息

    self.lastIncoming[talker] = text;
    NSTimeInterval sinceEnter = [NSDate timeIntervalSinceReferenceDate] - self.chatEnterTime;
    if (cfg.onlyLatest || sinceEnter < kChatEnterSuppress) {
        // 防抖：300ms 内以最新一条为准。
        // 只分析最新模式恒成立；分析所有消息模式下，进聊天页 2 秒内的初始布局风暴也只分析最新一条，避免历史消息洪水。
        NSString *snap = text;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOnlyLatestDebounce * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self.lastIncoming[talker] isEqualToString:snap])
                [self maybeAnalyze:text talker:talker anchorView:anchorView container:container force:NO];
        });
    } else {
        [self maybeAnalyze:text talker:talker anchorView:anchorView container:container force:NO];
    }
}

- (void)forceAnalyzeText:(NSString *)text talker:(NSString *)talker
             anchorView:(UIView *)anchorView container:(UIView *)container {
    [self maybeAnalyze:text talker:talker anchorView:anchorView container:container force:YES];
}

#pragma mark - 去重 / 限流 / 缓存
- (NSString *)cacheKey:(NSString *)talker text:(NSString *)text {
    return [NSString stringWithFormat:@"%@\n%@", talker, text];
}
- (BOOL)allowCall {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval hourAgo = now - 3600;
    NSMutableArray *keep = [NSMutableArray array];
    for (NSDate *d in self.callTimes) if (d.timeIntervalSinceReferenceDate > hourAgo) [keep addObject:d];
    self.callTimes = keep;
    return self.callTimes.count < [WXSubtextConfig shared].maxCallsPerHour;
}
- (void)maybeAnalyze:(NSString *)text talker:(NSString *)talker
          anchorView:(UIView *)anchorView container:(UIView *)container force:(BOOL)force {
    WXSubtextConfig *cfg = [WXSubtextConfig shared];
    self.trackedText = text; // 供滚动跟随与 cell 复用检测
    NSString *key = [self cacheKey:talker text:text];
    // 缓存命中：直接渲染
    WXSubtextAnalysis *cached = self.cache[key];
    if (cached && [[NSDate date] timeIntervalSinceDate:self.cacheTime[key]] < kCacheTTL) {
        [self render:cached talker:talker anchorView:anchorView container:container];
        return;
    }
    if ([self.inflight containsObject:key]) { WXSubtextLogMessage(@"[WXSubtext] 分析跳过：相同请求在途"); return; }
    if (!force && ![self allowCall]) { WXSubtextLogMessage(@"[WXSubtext] 分析跳过：触发每小时限流"); return; } // 触发限流则跳过（手动触发不受限）
    [self.inflight addObject:key];
    [self.callTimes addObject:[NSDate date]];

    // 上下文：最近 contextSize 条（不含当前这条，对应 Android 的 ContextBuffer 行为）
    // buffer 已持久化（每会话 100 条），记录越多上下文越准
    NSArray *buf = self.buffers[talker] ?: @[];
    NSInteger total = (NSInteger)buf.count - 1; // 排除当前这条
    NSInteger n = MIN(total, MAX((NSInteger)cfg.contextSize, 1));
    NSString *ctx = @"";
    if (n > 0) ctx = [[buf subarrayWithRange:NSMakeRange(buf.count - 1 - n, n)]
                       componentsJoinedByString:@"\n"];
    NSString *msg = text;
    if (cfg.desensitize) msg = [WXSubtextDesensitizer desensitize:text customWords:cfg.sensitiveWords];
    NSString *ctxD = cfg.desensitize ? [WXSubtextDesensitizer desensitize:ctx customWords:cfg.sensitiveWords] : ctx;

    // 先展示 loading 卡片
    WXSubtextCardView *card = [self makeCardNear:anchorView in:container];
    [card showLoading];
    __weak typeof(self) ws = self;
    [WXSubtextNetwork analyseWithRelation:cfg.relationDefault context:ctxD message:msg
        completion:^(WXSubtextAnalysis *a) {
            __strong typeof(ws) s = ws; if (!s) return;
            [s.inflight removeObject:key];
            if (a.ok) { s.cache[key] = a; s.cacheTime[key] = [NSDate date]; }
            if (card.superview) { // 卡片还在才更新，避免过时回调乱写
                if (a.ok) [card showAnalysis:a collapseTop1:cfg.collapseToTop1];
                else {
                    __weak WXSubtextCardView *wc = card;
                    [card showError:a.error];
                    card.onRetry = ^{ __strong WXSubtextCardView *c = wc;
                        [c showLoading];
                        [s maybeAnalyze:text talker:talker anchorView:anchorView container:container force:YES]; };
                }
            }
        }];
}

#pragma mark - 卡片定位与渲染
- (WXSubtextCardView *)makeCardNear:(UIView *)anchor in:(UIView *)container {
    [self.currentCard removeFromSuperview];
    CGRect af = anchor ? [anchor.superview convertRect:anchor.frame toView:container] : CGRectMake(20, 120, 200, 40);
    CGFloat w = MIN(MAX(af.size.width, 200), 280);
    CGFloat x = MIN(MAX(af.origin.x, 12), container.bounds.size.width - w - 12);
    CGFloat y = af.origin.y + af.size.height + 6;
    WXSubtextCardView *card = [[WXSubtextCardView alloc] initWithFrame:CGRectMake(x, y, w, 120)];
    card.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
    __weak typeof(self) ws = self;
    card.onClose = ^{ ws.currentCard = nil; };
    [container addSubview:card];
    self.currentCard = card;
    // 记录跟踪信息：滚动时让卡片跟随这条消息
    self.trackedAnchor = anchor;
    self.trackedContainer = container;
    return card;
}
- (void)render:(WXSubtextAnalysis *)a talker:(NSString *)talker
    anchorView:(UIView *)anchorView container:(UIView *)container {
    WXSubtextCardView *card = [self makeCardNear:anchorView in:container];
    [card showAnalysis:a collapseTop1:[WXSubtextConfig shared].collapseToTop1];
}

- (void)leaveChat {
    [self.currentCard removeFromSuperview];
    self.currentCard = nil;
    self.trackedAnchor = nil;
    self.trackedContainer = nil;
    self.trackedText = nil;
    [self saveHistory]; // 离开聊天页时落盘
}

- (void)noteChatEntered {
    self.chatEnterTime = [NSDate timeIntervalSinceReferenceDate];
}

// 聊天列表滚动：卡片跟随所分析的消息移动；消息滚出屏幕则隐藏，滚回再显示；
// cell 被复用给别的消息则直接移除卡片
- (void)chatDidScroll {
    WXSubtextCardView *card = self.currentCard;
    UIView *anchor = self.trackedAnchor;
    UIView *container = self.trackedContainer;
    if (!card || !anchor || !container) return;
    if (!anchor.window) { card.hidden = YES; return; }
    // cell 复用检测
    UIView *v = anchor;
    while (v && ![v isKindOfClass:[UITableViewCell class]] && ![v isKindOfClass:[UICollectionViewCell class]])
        v = v.superview;
    if (v) {
        NSString *cur = objc_getAssociatedObject(v, @"wxst_last");
        if (cur && self.trackedText && ![cur isEqualToString:self.trackedText]) {
            [card removeFromSuperview];
            self.currentCard = nil;
            self.trackedAnchor = nil;
            return;
        }
    }
    card.hidden = NO;
    CGRect af = [anchor.superview convertRect:anchor.frame toView:container];
    CGFloat w = card.frame.size.width, h = card.frame.size.height;
    CGFloat x = MIN(MAX(af.origin.x, 12), container.bounds.size.width - w - 12);
    CGFloat y = af.origin.y + af.size.height + 6;
    CGFloat maxY = container.bounds.size.height - h - 12;
    if (y > maxY) y = MAX(12, maxY);
    card.frame = CGRectMake(x, y, w, h);
}
@end
