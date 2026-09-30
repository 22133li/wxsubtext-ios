#import <Foundation/Foundation.h>
@class WXSubtextAnalysis;

// 网络层：与 Android 版 DeepSeekClient 等价，POST OpenAI 兼容的 /chat/completions。
// baseURL/apiKey/model/timeout 全部走 WXSubtextConfig。
@interface WXSubtextNetwork : NSObject
+ (void)analyseWithRelation:(NSString *)relation
                   context:(NSString *)context
                   message:(NSString *)message
                completion:(void(^)(WXSubtextAnalysis *analysis))completion;
@end
