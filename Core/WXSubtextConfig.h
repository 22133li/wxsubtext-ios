#import <Foundation/Foundation.h>

// 配置：从 /var/mobile/Library/Preferences/com.haoran.wxsubtext.plist 读取（CFPreferences，
// 微信进程内直接可读）。可用 Filza 直接编辑该 plist，或等后续的设置面板。
// 键名与 Android 版 Config 保持一致。
@interface WXSubtextConfig : NSObject
@property (nonatomic, assign) BOOL enabled;            // 启用分析，默认 YES
@property (nonatomic, assign) BOOL analyzeAllContacts;// 所有联系人都分析，默认 NO（只分析白名单）
@property (nonatomic, copy)   NSString *apiKey;       // 默认空
@property (nonatomic, copy)   NSString *baseURL;      // 默认 DeepSeek
@property (nonatomic, copy)   NSString *model;        // 默认 deepseek-chat
@property (nonatomic, copy)   NSString *relationDefault; // 默认关系：lover（伴侣）/friend/colleague/…
@property (nonatomic, assign) BOOL desensitize;       // 上传前脱敏，默认 YES
@property (nonatomic, copy)   NSArray<NSString *> *sensitiveWords; // 自定义敏感词
@property (nonatomic, assign) NSInteger contextSize;  // 上下文条数，默认 5
@property (nonatomic, assign) BOOL collapseToTop1;    // 卡片默认只展开第一条，默认 YES
@property (nonatomic, assign) BOOL onlyLatest;        // 只分析最新一条，默认 YES
@property (nonatomic, assign) NSInteger maxCallsPerHour; // 默认 60
@property (nonatomic, assign) NSInteger timeoutMs;    // 默认 30000（iOS 网络比 Android 超时放宽）
@property (nonatomic, copy)   NSSet<NSString *> *enabledTalkers; // 白名单（会话标题），analyzeAllContacts=NO 时生效
+ (instancetype)shared;
- (void)reload;
- (BOOL)shouldAnalyzeTalker:(NSString *)talker;
@end
