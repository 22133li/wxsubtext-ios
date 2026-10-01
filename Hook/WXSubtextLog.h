#import <Foundation/Foundation.h>

// 双写日志：NSLog（系统统一日志）+ 微信沙盒 Documents/wxsubtext.log（Filza 可见）。
// 沙盒内路径示例：/var/mobile/Containers/Data/Application/<UUID>/Documents/wxsubtext.log
// 超过 256KB 自动清空重写，避免无限增长。
void WXSubtextLogMessage(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
