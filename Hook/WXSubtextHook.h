#import <Foundation/Foundation.h>

// Hook 层：微信聊天页发现 + 消息 cell 文本抓取 + 卡片挂载。
// 策略是运行时发现（不硬编码混淆类名）：
//  1. swizzle UIViewController.viewDidAppear/viewDidDisappear，发现疑似聊天页；
//  2. swizzle UITableViewCell/UICollectionViewCell.layoutSubviews，在已确认的聊天 table 内抓取文本；
//  3. 文本最长的 UILabel 即消息正文；按气泡左右位置判定方向；
//  4. 卡片以浮层形式锚定在气泡下方（避免改动微信 cell 布局，更稳）。
// 首次运行会在系统日志打出候选类名（grep WXSubtext），回传后可收紧为精确 hook。
@interface WXSubtextHook : NSObject
+ (void)install;
@end
