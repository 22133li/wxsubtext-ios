#import <Foundation/Foundation.h>

// 脱敏：与 Android 版 Desensitizer 规则一一对应。
// 手机号/证件号/银行卡/金额/邮箱/链接/地址/日期 -> 占位符；自定义敏感词 -> [隐去]
@interface WXSubtextDesensitizer : NSObject
+ (NSString *)desensitize:(NSString *)text customWords:(NSArray<NSString *> *)words;
@end
