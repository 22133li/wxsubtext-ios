#import "WXSubtextSettingsHook.h"
#import "../UI/WXSubtextSettingsVC.h"
#import <objc/runtime.h>

#import "WXSubtextLog.h"

@interface WXSubtextSettingsHook ()
+ (void)tryInject:(UIViewController *)vc isRetry:(BOOL)isRetry;
+ (void)retryLater:(UIViewController *)vc tableView:(UITableView *)tv;
@end
#define WXLog(fmt, ...) WXSubtextLogMessage(@"[WXSubtext] " fmt, ##__VA_ARGS__)

static char kProxyKey;

// dataSource/delegate 代理：在顶部插入一个 section（section 0 是「潜台词」入口，
// 原对象的 section 整体后移一位），其余方法做位移后透传给原对象
@interface WXSubtextDSProxy : NSProxy <UITableViewDataSource, UITableViewDelegate> {
    id _ds;
    id _dg;
    __weak UIViewController *_host;
}
- (instancetype)initWithDataSource:(id)ds delegate:(id)dg host:(UIViewController *)host;
@end

@implementation WXSubtextDSProxy

- (instancetype)initWithDataSource:(id)ds delegate:(id)dg host:(UIViewController *)host {
    _ds = ds; _dg = dg; _host = host;
    return self;
}

static NSInteger origSections(id ds, UITableView *tv) {
    if ([ds respondsToSelector:@selector(numberOfSectionsInTableView:)])
        return [ds numberOfSectionsInTableView:tv];
    return 1;
}

// 原坐标 section -> 代理坐标（+1）；代理坐标 -> 原坐标（-1）
static NSIndexPath *shiftUp(NSIndexPath *ip) {
    return [NSIndexPath indexPathForRow:ip.row inSection:ip.section + 1];
}
static NSIndexPath *shiftDown(NSIndexPath *ip) {
    return [NSIndexPath indexPathForRow:ip.row inSection:ip.section - 1];
}

#pragma mark - 显式实现（顶部的 section 0）

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return origSections(_ds, tv) + 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    return [_ds tableView:tv numberOfRowsInSection:s - 1];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"wxst_settings_entry"];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:@"wxst_settings_entry"];
            c.textLabel.text = @"潜台词";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return c;
    }
    return [_ds tableView:tv cellForRowAtIndexPath:shiftDown(ip)];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        WXSubtextSettingsVC *svc = [[WXSubtextSettingsVC alloc] init];
        [_host.navigationController pushViewController:svc animated:YES];
        return;
    }
    if ([_dg respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)])
        [_dg tableView:tv didSelectRowAtIndexPath:shiftDown(ip)];
}

- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return ip;
    if ([_dg respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)]) {
        NSIndexPath *r = [_dg tableView:tv willSelectRowAtIndexPath:shiftDown(ip)];
        return r ? shiftUp(r) : nil;
    }
    return ip;
}

- (BOOL)tableView:(UITableView *)tv shouldHighlightRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return YES;
    if ([_dg respondsToSelector:@selector(tableView:shouldHighlightRowAtIndexPath:)])
        return [_dg tableView:tv shouldHighlightRowAtIndexPath:shiftDown(ip)];
    return YES;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return 48;
    if ([_dg respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)])
        return [_dg tableView:tv heightForRowAtIndexPath:shiftDown(ip)];
    return 44;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"插件";
    if ([_ds respondsToSelector:@selector(tableView:titleForHeaderInSection:)])
        return [_ds tableView:tv titleForHeaderInSection:s - 1];
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return nil;
    if ([_ds respondsToSelector:@selector(tableView:titleForFooterInSection:)])
        return [_ds tableView:tv titleForFooterInSection:s - 1];
    return nil;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s {
    if (s == 0) return 28;
    if ([_dg respondsToSelector:@selector(tableView:heightForHeaderInSection:)])
        return [_dg tableView:tv heightForHeaderInSection:s - 1];
    return 28;
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    if (s == 0) return 0.01;
    if ([_dg respondsToSelector:@selector(tableView:heightForFooterInSection:)])
        return [_dg tableView:tv heightForFooterInSection:s - 1];
    return 0.01;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    if (s == 0) return nil;
    if ([_dg respondsToSelector:@selector(tableView:viewForHeaderInSection:)])
        return [_dg tableView:tv viewForHeaderInSection:s - 1];
    return nil;
}

- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    if (s == 0) return nil;
    if ([_dg respondsToSelector:@selector(tableView:viewForFooterInSection:)])
        return [_dg tableView:tv viewForFooterInSection:s - 1];
    return nil;
}

#pragma mark - NSProxy 透传（带 section 位移）

- (BOOL)respondsToSelector:(SEL)sel {
    static NSSet *own = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ own = [NSSet setWithArray:@[
        @"numberOfSectionsInTableView:",
        @"tableView:numberOfRowsInSection:",
        @"tableView:cellForRowAtIndexPath:",
        @"tableView:didSelectRowAtIndexPath:",
        @"tableView:willSelectRowAtIndexPath:",
        @"tableView:shouldHighlightRowAtIndexPath:",
        @"tableView:heightForRowAtIndexPath:",
        @"tableView:titleForHeaderInSection:",
        @"tableView:titleForFooterInSection:",
        @"tableView:heightForHeaderInSection:",
        @"tableView:heightForFooterInSection:",
        @"tableView:viewForHeaderInSection:",
        @"tableView:viewForFooterInSection:",
    ]]; });
    if ([own containsObject:NSStringFromSelector(sel)]) return YES;
    if ([_ds respondsToSelector:sel]) return YES;
    if ([_dg respondsToSelector:sel]) return YES;
    return NO;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *sig = [_ds methodSignatureForSelector:sel];
    if (!sig) sig = [_dg methodSignatureForSelector:sel];
    return sig;
}

- (void)forwardInvocation:(NSInvocation *)inv {
    // 透传调用里的 NSIndexPath 需要回拨一位（代理坐标 -> 原坐标）；
    // 指向 section 0（我们的入口）的调用直接吞掉，不透传给原对象
    NSMethodSignature *sig = inv.methodSignature;
    BOOL drop = NO;
    for (NSUInteger i = 2; i < sig.numberOfArguments; i++) {
        const char *t = [sig getArgumentTypeAtIndex:i];
        if (t[0] != '@') continue;
        __unsafe_unretained id arg = nil;
        [inv getArgument:&arg atIndex:i];
        if ([arg isKindOfClass:[NSIndexPath class]]) {
            NSIndexPath *ip = (NSIndexPath *)arg;
            if (ip.section == 0) { drop = YES; break; }
            NSIndexPath *shifted = shiftDown(ip);
            [inv setArgument:&shifted atIndex:i];
        }
    }
    if (drop) {
        NSUInteger len = sig.methodReturnLength;
        if (len > 0 && len <= 64) {
            unsigned char z[64] = {0};
            [inv setReturnValue:z];
        }
        return;
    }
    if ([_ds respondsToSelector:inv.selector]) { [inv invokeWithTarget:_ds]; return; }
    if ([_dg respondsToSelector:inv.selector]) { [inv invokeWithTarget:_dg]; return; }
}

@end

#pragma mark - 设置页发现与注入

@implementation WXSubtextSettingsHook

// 设置页主列表的关键词（多重校验，避免误判）
static NSSet *settingsKeywords(void) {
    static NSSet *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [NSSet setWithArray:@[
        @"账号与安全", @"新消息通知", @"隐私", @"通用", @"帮助与反馈", @"关于微信",
    ]]; });
    return s;
}

static UITableView *findTableView(UIView *root) {
    if ([root isKindOfClass:[UITableView class]]) return (UITableView *)root;
    for (UIView *s in root.subviews) {
        UITableView *r = findTableView(s);
        if (r) return r;
    }
    return nil;
}

// 收集 view 子树里所有 UILabel 的文本（微信设置页用自定义 cell，cell.textLabel 为空）
static void collectLabelTexts(UIView *v, NSMutableArray *out) {
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = [(UILabel *)v text];
        t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length) [out addObject:t];
    }
    for (UIView *s in v.subviews) collectLabelTexts(s, out);
}

static char kRetryKey;

+ (void)tryInjectSettingsEntry:(UIViewController *)vc {
    [self tryInject:vc isRetry:NO];
}

+ (void)tryInject:(UIViewController *)vc isRetry:(BOOL)isRetry {
    @try {
        if (!vc.view || !vc.navigationController) return;
        NSString *title = vc.navigationItem.title;
        if (!title.length) title = vc.title;
        if (![title isEqualToString:@"设置"]) return;      // 只要主设置页
        UITableView *tv = findTableView(vc.view);
        if (!tv) return;
        id cur = objc_getAssociatedObject(tv, &kProxyKey);
        if (cur && tv.dataSource == cur) return;            // 已注入且未被替换
        if (!isRetry) {
            // 每次新进入设置页都清零重试计数，避免某次 cell 加载慢耗尽次数后永久不再注入
            objc_setAssociatedObject(tv, &kRetryKey, @(0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // 诊断日志：确认检测走到了哪一步
        WXLog(@"设置页候选: %@ table=%@ 可见cell=%lu", NSStringFromClass([vc class]),
              tv ? NSStringFromClass([tv class]) : @"nil", (unsigned long)tv.visibleCells.count);
        id ds = tv.dataSource;
        if (!ds) { [self retryLater:vc tableView:tv]; return; }
        // diffable dataSource 不碰，避免破坏快照机制
        Class diffable = NSClassFromString(@"UITableViewDiffableDataSource");
        if (diffable && [ds isKindOfClass:diffable]) { WXLog(@"设置页 dataSource 是 diffable，跳过"); return; }
        // 关键词校验：遍历可见 cell 内所有 UILabel（微信用自定义 cell，textLabel 为空）
        int hits = 0;
        NSSet *kw = settingsKeywords();
        NSArray *cells = tv.visibleCells;
        for (UITableViewCell *cell in cells) {
            NSMutableArray *texts = [NSMutableArray array];
            collectLabelTexts(cell, texts);
            for (NSString *t in texts) {
                BOOL hit = NO;
                for (NSString *k in kw) { if ([t containsString:k]) { hit = YES; break; } }
                if (hit) { hits++; break; }
            }
            if (hits >= 2) break;
        }
        WXLog(@"设置页关键词命中 %d", hits);
        if (hits < 2) { [self retryLater:vc tableView:tv]; return; }
        WXSubtextDSProxy *proxy = [[WXSubtextDSProxy alloc] initWithDataSource:ds
                                                                     delegate:tv.delegate
                                                                         host:vc];
        objc_setAssociatedObject(tv, &kProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tv.dataSource = (id<UITableViewDataSource>)proxy;
        tv.delegate = (id<UITableViewDelegate>)proxy;
        [tv reloadData];
        objc_setAssociatedObject(tv, &kRetryKey, @(0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WXLog(@"设置页注入成功：已在顶部插入「潜台词」入口");
    } @catch (NSException *e) {
        WXLog(@"设置页注入异常: %@", e);
    }
}

+ (void)retryLater:(UIViewController *)vc tableView:(UITableView *)tv {
    NSNumber *n = objc_getAssociatedObject(tv, &kRetryKey);
    if ([n intValue] >= 2) return;
    objc_setAssociatedObject(tv, &kRetryKey, @([n intValue] + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIViewController *wvc = vc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *s = wvc;
        if (s && s.view.window) [self tryInject:s isRetry:YES];
    });
}

@end
