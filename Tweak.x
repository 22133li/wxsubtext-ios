#import <UIKit/UIKit.h>
#import "Hook/WXSubtextHook.h"
#import "Hook/WXSubtextLog.h"

// 潜台词 iOS 版入口：微信启动 3 秒后安装 hook（对齐 Android 版的延迟安装策略）
%ctor {
    WXSubtextLogMessage(@"[WXSubtext] dylib 已加载，3 秒后安装 hook");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            [WXSubtextHook install];
        } @catch (NSException *e) {
            NSLog(@"[WXSubtext] install 异常: %@", e);
        }
    });
}
