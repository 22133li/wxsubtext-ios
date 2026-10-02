#import "WXSubtextHook.h"
#import "WXSubtextSettingsHook.h"
#import "../Core/WXSubtextCore.h"
#import <objc/runtime.h>

#import "WXSubtextLog.h"
#define WXLog(fmt, ...) WXSubtextLogMessage(@"[WXSubtext] " fmt, ##__VA_ARGS__)

// 已确认的聊天页（弱引用，避免野指针）
static __weak UIViewController *gChatVC = nil;
static __weak UIScrollView *gChatScroll = nil;
static NSString *gTalker = nil;
static void *kKVOContext = &kKVOContext;

// 前向声明（定义在文件尾部）
static void (*orig_collCellLayout)(id, SEL);
static void hook_collCellLayout(id self, SEL _cmd);
static void handleCellLayout(UIView *cell);

#pragma mark - 文本抓取（MsgExtractor 的 UIKit 版）

static BOOL isFileMessageText(NSString *t);

static BOOL isNoiseText(NSString *t) {
    if (!t.length || t.length > 500) return YES;
    static NSRegularExpression *timeRe, *weekRe, *dateRe, *ampmRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 冒号兼容半角 : 与全角 ：；\s 已含全角空格 U+3000
        timeRe = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}[:：]\\d{2}([:：]\\d{2})?$" options:0 error:nil];
        weekRe = [NSRegularExpression regularExpressionWithPattern:@"^(星期[一二三四五六日天]|周[一二三四五六日天])\\s*\\d{1,2}[:：]\\d{2}([:：]\\d{2})?$" options:0 error:nil];
        dateRe = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}月\\d{1,2}日" options:0 error:nil];
        ampmRe = [NSRegularExpression regularExpressionWithPattern:@"^(上午|下午|早上|晚上|凌晨|中午)\\s*\\d{1,2}[:：]\\d{2}([:：]\\d{2})?$" options:0 error:nil];
    });
    NSRange r = NSMakeRange(0, t.length);
    if ([timeRe numberOfMatchesInString:t options:0 range:r]) return YES;
    if ([weekRe numberOfMatchesInString:t options:0 range:r]) return YES;
    if ([dateRe numberOfMatchesInString:t options:0 range:r]) return YES;
    if ([ampmRe numberOfMatchesInString:t options:0 range:r]) return YES;
    if ([t containsString:@"撤回了一条消息"]) return YES;
    if ([t containsString:@"正在输入"]) return YES;
    // 通话记录类系统消息（居中显示的语音/视频通话记录）
    if ([t containsString:@"通话时长"]) return YES;
    if ([t isEqualToString:@"已取消"] || [t isEqualToString:@"对方已取消"] ||
        [t isEqualToString:@"已拒绝"] || [t isEqualToString:@"对方已拒绝"]) return YES;
    if ([t containsString:@"无应答"] || [t containsString:@"忙线未接听"] ||
        [t containsString:@"对方忙线中"]) return YES;
    // 文件消息：气泡内 "文件名\n12.5 MB" 两行结构
    if (isFileMessageText(t)) return YES;
    return NO;
}

// 微信文件消息气泡文本特征：第一行文件名（含扩展名），第二行文件大小
static BOOL isFileMessageText(NSString *t) {
    NSArray *lines = [t componentsSeparatedByString:@"\n"];
    if (lines.count < 2) return NO;
    NSString *first = [lines[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *second = [lines[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!first.length || !second.length) return NO;
    static NSRegularExpression *reSize = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reSize = [NSRegularExpression regularExpressionWithPattern:@"^\\d+(\\.\\d+)?\\s*(B|KB|MB|GB)$"
                                                          options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSRange r = NSMakeRange(0, second.length);
    if (![reSize numberOfMatchesInString:second options:0 range:r]) return NO;
    NSString *ext = [[first pathExtension] lowercaseString];
    static NSSet *exts = nil;
    static dispatch_once_t once2;
    dispatch_once(&once2, ^{
        exts = [NSSet setWithObjects:@"pdf",@"doc",@"docx",@"xls",@"xlsx",@"ppt",@"pptx",
                @"txt",@"rtf",@"csv",@"zip",@"rar",@"7z",@"tar",@"gz",
                @"mp3",@"wav",@"m4a",@"mp4",@"mov",@"avi",@"mkv",
                @"jpg",@"jpeg",@"png",@"gif",@"bmp",@"webp",@"heic",
                @"apk",@"ipa",@"exe",@"dmg", nil];
    });
    return [exts containsObject:ext];
}

// UILabel 取完整文本：微信聊天文本用 attributedText（富文本），text 为空时回退取 attributedText.string
static NSString *labelFullText(UILabel *l) {
    NSString *t = l.text;
    if (!t.length && l.attributedText) t = l.attributedText.string;
    return [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

// 返回最长有效文本的 UILabel（BFS 遍历 contentView）
static UILabel *findContentLabel(UIView *root) {
    UILabel *best = nil;
    NSUInteger bestLen = 0;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    while (q.count) {
        UIView *v = q[0]; [q removeObjectAtIndex:0];
        if (!v || v.hidden) continue;
        if ([v isKindOfClass:[UILabel class]]) {
            NSString *t = labelFullText((UILabel *)v);
            if (!isNoiseText(t) && t.length > bestLen) { best = (UILabel *)v; bestLen = t.length; }
        }
        for (UIView *s in v.subviews) [q addObject:s];
    }
    return best;
}

// 方向判定：label 中心在 cell 左半 → 对方；右半 → 自己；中间 40pt 死区跳过
static int directionOfLabel(UILabel *label, UIView *cell) {
    CGPoint c = [label.superview convertPoint:label.center toView:cell];
    CGFloat mid = cell.bounds.size.width / 2;
    if (c.x < mid - 20) return -1; // 对方
    if (c.x > mid + 20) return 1;  // 自己
    return 0;
}

#pragma mark - 聊天页发现

// 从 VC 的 view 里找消息列表（UITableView / UICollectionView）
static UIScrollView *findChatScrollView(UIView *root) {
    if ([root isKindOfClass:[UITableView class]] || [root isKindOfClass:[UICollectionView class]])
        return (UIScrollView *)root;
    for (UIView *s in root.subviews) {
        UIScrollView *r = findChatScrollView(s);
        if (r) return r;
    }
    return nil;
}

// 启发式：VC 类名含 chat（忽略大小写），或其 cell 类名含 message/msg/chat/bubble
// 排除主 TabBar（会话列表页的 cell 类名也含 msg，会误判）
static BOOL looksLikeChatVC(UIViewController *vc) {
    NSString *name = NSStringFromClass([vc class]);
    if ([name rangeOfString:@"TabBar" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    if ([name rangeOfString:@"chat" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    UIScrollView *sv = findChatScrollView(vc.view);
    if ([sv isKindOfClass:[UITableView class]]) {
        for (UITableViewCell *cell in [(UITableView *)sv visibleCells]) {
            NSString *cn = NSStringFromClass([cell class]);
            NSString *low = cn.lowercaseString;
            if ([low containsString:@"message"] || [low containsString:@"msg"] ||
                [low containsString:@"chat"] || [low containsString:@"bubble"]) return YES;
        }
    } else if ([sv isKindOfClass:[UICollectionView class]]) {
        for (UICollectionViewCell *cell in [(UICollectionView *)sv visibleCells]) {
            NSString *low = NSStringFromClass([cell class]).lowercaseString;
            if ([low containsString:@"message"] || [low containsString:@"msg"] ||
                [low containsString:@"chat"] || [low containsString:@"bubble"]) return YES;
        }
    }
    return NO;
}

static NSString *talkerOfVC(UIViewController *vc) {
    NSString *t = vc.navigationItem.title;
    if (!t.length) t = vc.title;
    return t ?: @"";
}

#pragma mark - KVO：滚动时关掉浮层卡片

@interface WXSubtextKVOHolder : NSObject @end
@implementation WXSubtextKVOHolder
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj change:(NSDictionary *)ch context:(void *)ctx {
    if (ctx == kKVOContext) {
        // 滚动时卡片跟随消息，而不是直接关掉
        [[WXSubtextCore shared] chatDidScroll];
    }
}
@end
static WXSubtextKVOHolder *gKVO = nil;

#pragma mark - swizzle 实现

static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    @try {
        UIViewController *vc = self;
        // 打日志：所有全屏 VC 的类名，方便收紧判定（只在首次出现时打一次）
        static NSMutableSet *seen;
        static dispatch_once_t t;
        dispatch_once(&t, ^{ seen = [NSMutableSet set]; });
        NSString *cn = NSStringFromClass([vc class]);
        if (![seen containsObject:cn]) {
            [seen addObject:cn];
            NSString *vt = vc.navigationItem.title;
            if (!vt.length) vt = vc.title;
            WXLog(@"VC 出现: %@ title=%@", cn, vt ?: @"");
        }
        if (looksLikeChatVC(vc)) {
            UIScrollView *sv = findChatScrollView(vc.view);
            if (sv && sv != gChatScroll) {
                gChatVC = vc; gChatScroll = sv; gTalker = talkerOfVC(vc);
                [[WXSubtextCore shared] noteChatEntered];
                WXLog(@"进入聊天页: %@ talker=%@ scroll=%@", cn, gTalker, NSStringFromClass([sv class]));
                if (!gKVO) gKVO = [[WXSubtextKVOHolder alloc] init];
                @try { [sv addObserver:gKVO forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:kKVOContext]; }
                @catch (NSException *e) {}
                // 补抓：cell 的 layoutSubviews 在 viewDidAppear 之前已触发完毕，
                // 此时 gChatScroll 才刚就绪，手动对可见 cell 补一次抓取，否则进页消息全部漏掉。
                // 注意 visibleCells 不保证按 Y 排序，按纵坐标排好序再抓，保证"最新一条"真是时间上最新的
                if ([sv isKindOfClass:[UITableView class]]) {
                    UITableView *tv = (UITableView *)sv;
                    NSArray *sorted = [[tv visibleCells] sortedArrayUsingComparator:^NSComparisonResult(UITableViewCell *a, UITableViewCell *b) {
                        CGRect fa = [a.superview convertRect:a.frame toView:tv];
                        CGRect fb = [b.superview convertRect:b.frame toView:tv];
                        if (fa.origin.y < fb.origin.y) return NSOrderedAscending;
                        if (fa.origin.y > fb.origin.y) return NSOrderedDescending;
                        return NSOrderedSame;
                    }];
                    for (UITableViewCell *cell in sorted) handleCellLayout(cell);
                } else if ([sv isKindOfClass:[UICollectionView class]]) {
                    UICollectionView *cv = (UICollectionView *)sv;
                    NSArray *sorted = [[cv visibleCells] sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *a, UICollectionViewCell *b) {
                        CGRect fa = [a.superview convertRect:a.frame toView:cv];
                        CGRect fb = [b.superview convertRect:b.frame toView:cv];
                        if (fa.origin.y < fb.origin.y) return NSOrderedAscending;
                        if (fa.origin.y > fb.origin.y) return NSOrderedDescending;
                        return NSOrderedSame;
                    }];
                    for (UICollectionViewCell *cell in sorted) handleCellLayout(cell);
                }
            } else if (sv) {
                gTalker = talkerOfVC(vc); // 同一列表，标题可能更新
            }
        }
        // 微信设置页：追加「潜台词」设置入口（1.01）
        [WXSubtextSettingsHook tryInjectSettingsEntry:vc];
    } @catch (NSException *e) { WXLog(@"viewDidAppear 处理异常: %@", e); }
}

static void (*orig_viewDidDisappear)(id, SEL, BOOL);
static void hook_viewDidDisappear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidDisappear(self, _cmd, animated);
    if (self == gChatVC) {
        @try { [gChatScroll removeObserver:gKVO forKeyPath:@"contentOffset"]; } @catch (NSException *e) {}
        gChatVC = nil; gChatScroll = nil;
        [[WXSubtextCore shared] leaveChat];
        WXLog(@"离开聊天页");
    }
}

// cell 布局完成后的共用抓取逻辑（对应 Android 的 onBindViewHolder 回调）
static void handleCellLayout(UIView *cell) {
    @try {
        UIScrollView *sv = gChatScroll;
        if (!sv || !gTalker) return;
        // 确认这个 cell 属于当前聊天列表
        UIView *v = cell;
        BOOL inside = NO;
        while (v) { if (v == sv) { inside = YES; break; } v = v.superview; }
        if (!inside || !cell.window) return;
        UIView *content = nil;
        @try { content = [cell valueForKey:@"contentView"]; } @catch (NSException *e) {}
        if (!content) content = cell;
        UILabel *label = findContentLabel(content);
        if (!label) return;
        NSString *text = labelFullText(label);
        NSString *last = objc_getAssociatedObject(cell, @"wxst_last");
        if ([last isEqualToString:text]) return; // 去重
        objc_setAssociatedObject(cell, @"wxst_last", text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        int dir = directionOfLabel(label, cell);
        if (dir == 0) return;
        WXLog(@"抓到消息 dir=%@ talker=%@ text=%@", dir < 0 ? @"对方" : @"自己", gTalker,
              text.length > 30 ? [[text substringToIndex:30] stringByAppendingString:@"…"] : text);
        UIView *anchor = label.superview ?: label;
        UIViewController *vc = gChatVC;
        if (vc) [[WXSubtextCore shared] onMessageText:text isFromOther:(dir < 0)
                                              talker:gTalker anchorView:anchor container:vc.view];
    } @catch (NSException *e) { WXLog(@"cell 抓取异常: %@", e); }
}

// cell 布局完成后抓取（对应 Android 的 onBindViewHolder 回调）
static void (*orig_cellLayout)(id, SEL);
static void hook_cellLayout(id self, SEL _cmd) {
    orig_cellLayout(self, _cmd);
    handleCellLayout(self);
}

static void swizzle(Class cls, SEL sel, IMP newImp, void **origOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { WXLog(@"找不到方法 %@ %@", cls, NSStringFromSelector(sel)); return; }
    *origOut = (void *)method_getImplementation(m);
    method_setImplementation(m, newImp);
}

@implementation WXSubtextHook
+ (void)install {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        WXLog(@"安装 hook（微信 8.0.78 运行时发现模式）");
        swizzle([UIViewController class], @selector(viewDidAppear:), (IMP)hook_viewDidAppear, (void **)&orig_viewDidAppear);
        swizzle([UIViewController class], @selector(viewDidDisappear:), (IMP)hook_viewDidDisappear, (void **)&orig_viewDidDisappear);
        swizzle([UITableViewCell class], @selector(layoutSubviews), (IMP)hook_cellLayout, (void **)&orig_cellLayout);
        swizzle([UICollectionViewCell class], @selector(layoutSubviews), (IMP)hook_collCellLayout, (void **)&orig_collCellLayout);
        WXLog(@"hook 安装完成");
    });
}
@end

// UICollectionViewCell 独立的一组 orig 指针（与 UITableViewCell 的实现不同，不能共用）
static void (*orig_collCellLayout)(id, SEL) = NULL;
static void hook_collCellLayout(id self, SEL _cmd) {
    orig_collCellLayout(self, _cmd);
    handleCellLayout(self);
}
