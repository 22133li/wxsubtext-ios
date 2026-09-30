#import "WXSubtextSettingsHook.h"
#import "../UI/WXSubtextSettingsVC.h"
#import <objc/runtime.h>

#define WXLog(fmt, ...) NSLog(@"[WXSubtext] " fmt, ##__VA_ARGS__)

static char kProxyKey;

// dataSource/delegate 代理：只追加最后一个 section，其余方法全部透传给原对象
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

#pragma mark - 显式实现（追加的 section）

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return origSections(_ds, tv) + 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == origSections(_ds, tv)) return 1;
    return [_ds tableView:tv numberOfRowsInSection:s];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == origSections(_ds, tv)) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"wxst_settings_entry"];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:@"wxst_settings_entry"];
            c.textLabel.text = @"潜台词";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return c;
    }
    return [_ds tableView:tv cellForRowAtIndexPath:ip];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == origSections(_ds, tv)) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        WXSubtextSettingsVC *svc = [[WXSubtextSettingsVC alloc] init];
        [_host.navigationController pushViewController:svc animated:YES];
        return;
    }
    if ([_dg respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)])
        [_dg tableView:tv didSelectRowAtIndexPath:ip];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == origSections(_ds, tv)) return 48;
    if ([_dg respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)])
        return [_dg tableView:tv heightForRowAtIndexPath:ip];
    return 44;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == origSections(_ds, tv)) return @"插件";
    if ([_ds respondsToSelector:@selector(tableView:titleForHeaderInSection:)])
        return [_ds tableView:tv titleForHeaderInSection:s];
    return nil;
}

#pragma mark - NSProxy 透传

- (BOOL)respondsToSelector:(SEL)sel {
    static NSSet *own = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ own = [NSSet setWithArray:@[
        @"numberOfSectionsInTableView:",
        @"tableView:numberOfRowsInSection:",
        @"tableView:cellForRowAtIndexPath:",
        @"tableView:didSelectRowAtIndexPath:",
        @"tableView:heightForRowAtIndexPath:",
        @"tableView:titleForHeaderInSection:",
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

+ (void)tryInjectSettingsEntry:(UIViewController *)vc {
    @try {
        if (!vc.view || !vc.navigationController) return;
        NSString *title = vc.navigationItem.title;
        if (!title.length) title = vc.title;
        if (![title isEqualToString:@"设置"]) return;      // 只要主设置页
        UITableView *tv = findTableView(vc.view);
        if (!tv) return;
        id cur = objc_getAssociatedObject(tv, &kProxyKey);
        if (cur && tv.dataSource == cur) return;            // 已注入且未被替换
        id ds = tv.dataSource;
        if (!ds) return;
        // diffable dataSource 不碰，避免破坏快照机制
        Class diffable = NSClassFromString(@"UITableViewDiffableDataSource");
        if (diffable && [ds isKindOfClass:diffable]) return;
        // 关键词校验：可见 cell 里至少命中 2 个设置项
        int hits = 0;
        NSSet *kw = settingsKeywords();
        for (UITableViewCell *cell in tv.visibleCells) {
            NSString *t = cell.textLabel.text;
            if (!t.length) continue;
            for (NSString *k in kw) {
                if ([t containsString:k]) { hits++; break; }
            }
            if (hits >= 2) break;
        }
        if (hits < 2) return;
        WXSubtextDSProxy *proxy = [[WXSubtextDSProxy alloc] initWithDataSource:ds
                                                                     delegate:tv.delegate
                                                                         host:vc];
        objc_setAssociatedObject(tv, &kProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tv.dataSource = (id<UITableViewDataSource>)proxy;
        tv.delegate = (id<UITableViewDelegate>)proxy;
        [tv reloadData];
        WXLog(@"设置页注入成功：已追加「潜台词」入口");
    } @catch (NSException *e) {
        WXLog(@"设置页注入异常: %@", e);
    }
}

@end
