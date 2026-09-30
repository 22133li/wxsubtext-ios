#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 编排层：Android 版 SubtextCore 的 iOS 实现。
// 职责：维护每会话上下文缓冲、去重/缓存、每小时限流、触发 AI 分析、渲染卡片。
// Hook 层只需调用 -onMessageText:isFromOther:talker:anchorView:container:。
@interface WXSubtextCore : NSObject
+ (instancetype)shared;

// 有新消息行被绑定/展示时调用（anchorView=消息气泡视图，用于定位卡片；
// container=聊天页根视图，卡片加在这里）
- (void)onMessageText:(NSString *)text
          isFromOther:(BOOL)fromOther
               talker:(NSString *)talker
           anchorView:(UIView *)anchorView
            container:(UIView *)container;

// 手动触发某条消息的分析（长按菜单等入口调用）
- (void)forceAnalyzeText:(NSString *)text talker:(NSString *)talker
              anchorView:(UIView *)anchorView container:(UIView *)container;

// 离开聊天页时调用，清理卡片与上下文
- (void)leaveChat;
@end
