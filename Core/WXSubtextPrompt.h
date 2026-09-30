#import <Foundation/Foundation.h>

// Prompt：与 Android 版 PromptBuilder 逐字一致（system + user 模板）。
@interface WXSubtextPrompt : NSObject
+ (NSString *)systemPrompt;
+ (NSString *)userMessageWithRelation:(NSString *)relation
                             context:(NSString *)context
                       latestMessage:(NSString *)latest;
@end
