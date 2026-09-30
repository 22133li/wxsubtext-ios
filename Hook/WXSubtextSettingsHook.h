#import <UIKit/UIKit.h>

// 在微信「我 → 设置」页末尾追加一行「潜台词」，点进去打开 WXSubtextSettingsVC。
// 用 NSProxy 代理原 dataSource/delegate，只追加一个 section，其余全部透传，不动微信原有逻辑。
@interface WXSubtextSettingsHook : NSObject
+ (void)tryInjectSettingsEntry:(UIViewController *)vc;
@end
