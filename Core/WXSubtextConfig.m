#import "WXSubtextConfig.h"

static NSString * const kDomain = @"com.haoran.wxsubtext";

@implementation WXSubtextConfig
+ (instancetype)shared {
    static WXSubtextConfig *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; [s reload]; });
    return s;
}
static id pref(NSString *k) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)kDomain));
}
- (void)reload {
    id v;
    v = pref(@"Enabled");            self.enabled = v ? [v boolValue] : YES;
    v = pref(@"AnalyzeAllContacts"); self.analyzeAllContacts = v ? [v boolValue] : NO;
    v = pref(@"APIKey");             self.apiKey = [v isKindOfClass:[NSString class]] ? v : @"";
    v = pref(@"BaseURL");            self.baseURL = [v isKindOfClass:[NSString class]] && [v length] ? v : @"https://api.deepseek.com/v1/chat/completions";
    v = pref(@"Model");              self.model = [v isKindOfClass:[NSString class]] && [v length] ? v : @"deepseek-chat";
    v = pref(@"RelationDefault");    self.relationDefault = [v isKindOfClass:[NSString class]] && [v length] ? v : @"亲密关系（伴侣）";
    v = pref(@"Desensitize");        self.desensitize = v ? [v boolValue] : YES;
    v = pref(@"SensitiveWords");     self.sensitiveWords = [v isKindOfClass:[NSArray class]] ? v : @[];
    v = pref(@"ContextSize");        self.contextSize = v ? [v integerValue] : 20;
    v = pref(@"CollapseToTop1");     self.collapseToTop1 = v ? [v boolValue] : YES;
    v = pref(@"OnlyLatest");         self.onlyLatest = v ? [v boolValue] : YES;
    v = pref(@"MaxCallsPerHour");    self.maxCallsPerHour = v ? [v integerValue] : 60;
    v = pref(@"TimeoutMs");          self.timeoutMs = v ? [v integerValue] : 30000;
    v = pref(@"EnabledTalkers");
    self.enabledTalkers = [v isKindOfClass:[NSArray class]] ? [NSSet setWithArray:v] : [NSSet set];
}
- (BOOL)shouldAnalyzeTalker:(NSString *)talker {
    if (!self.enabled) return NO;
    if (self.analyzeAllContacts) return YES;
    return talker.length && [self.enabledTalkers containsObject:talker];
}
#pragma mark - 写入
- (void)writeValue:(id)v forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)v,
                             (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    [self reload];
}
- (void)writeBool:(BOOL)v forKey:(NSString *)key    { [self writeValue:@(v) forKey:key]; }
- (void)writeString:(NSString *)v forKey:(NSString *)key { [self writeValue:v ?: @"" forKey:key]; }
- (void)writeInteger:(NSInteger)v forKey:(NSString *)key { [self writeValue:@(v) forKey:key]; }
- (void)writeArray:(NSArray *)v forKey:(NSString *)key   { [self writeValue:v ?: @[] forKey:key]; }
@end
