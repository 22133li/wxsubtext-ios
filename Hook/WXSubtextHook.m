#import "WXSubtextHook.h"
#import "../Core/WXSubtextCore.h"
#import <objc/runtime.h>

#define WXLog(fmt, ...) NSLog(@"[WXSubtext] " fmt, ##__VA_ARGS__)

// 已确认的聊天页（弱引用，避免野指针）
static __weak UIViewController *gChatVC = nil;
static __weak UIScrollView *gChatScroll = nil;
static NSString *gTalker = nil;
static void *kKVOContext = &kKVOContext;

// 前向声明（定义在文件尾部）
static void (*orig_collCellLayout)(id, SEL);
static void hook_collCellLayout(id self, SEL _cmd);

#pragma mark - 文本抓取（MsgExtractor 的 UIKit 版）

static BOOL isNoiseText(NSString *t) {
    if (!t.length || t.length > 500) return YES;
    static NSRegularExpression *timeRe, *dateRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        timeRe = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}:\\d{2}$" options:0 error:nil];
        dateRe = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}月\\d{1,2}日" options:0 error:nil];
    });
    if ([timeRe numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)]) return YES;
    if ([dateRe numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)]) return YES;
    if ([t containsString:@"撤回了一条消息"]) return YES;
    if ([t isEqualToString:@"对方正在输入"]) return YES;
    return NO;
}

// 返回最长有效文本的 UILabel（BFS 遍历 contentView）
static UILabel *findContentLabel(UIView *root) {
    UILabel *best = nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    while (q.count) {
        UIView *v = q[0]; [q removeObjectAtIndex:0];
        if (!v || v.hidden || v.alpha < 0.01) continue;
        if ([v isKindOfClass:[UILabel class]]) {
            NSString *t = [(UILabel *)v text];
            t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!isNoiseText(t) && (!best || t.length > best.text.length)) best = (UILabel *)v;
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
static BOOL looksLikeChatVC(UIViewController *vc) {
    NSString *name = NSStringFromClass([vc class]);
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
        // 滚动位移较大时关卡片，避免错位
        [[WXSubtextCore shared] leaveChat];
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
            if ([cn rangeOfString:@"chat" options:NSCaseInsensitiveSearch].location != NSNotFound)
                WXLog(@"候选聊天 VC: %@", cn);
        }
        if (looksLikeChatVC(vc)) {
            UIScrollView *sv = findChatScrollView(vc.view);
            if (sv && sv != gChatScroll) {
                gChatVC = vc; gChatScroll = sv; gTalker = talkerOfVC(vc);
                WXLog(@"进入聊天页: %@ talker=%@ scroll=%@", cn, gTalker, NSStringFromClass([sv class]));
                if (!gKVO) gKVO = [[WXSubtextKVOHolder alloc] init];
                @try { [sv addObserver:gKVO forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:kKVOContext]; }
                @catch (NSException *e) {}
            } else if (sv) {
                gTalker = talkerOfVC(vc); // 同一列表，标题可能更新
            }
        }
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
        NSString *text = [label.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
