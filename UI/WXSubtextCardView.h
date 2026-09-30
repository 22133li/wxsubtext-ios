#import <UIKit/UIKit.h>
@class WXSubtextAnalysis;

// 分析卡片：Android 版 QuoteCardView 的 UIKit 实现。
// 三种状态：加载中 / 结果 / 错误（带重试）。结果区默认只展开第一条解读（collapseToTop1）。
@interface WXSubtextCardView : UIView
@property (nonatomic, copy) dispatch_block_t onClose;
@property (nonatomic, copy) void (^onRetry)(void);
- (void)showLoading;
- (void)showAnalysis:(WXSubtextAnalysis *)analysis collapseTop1:(BOOL)collapse;
- (void)showError:(NSString *)message;
@end
