#import "WXSubtextAnalysis.h"

@implementation WXSubtextOption @end

@implementation WXSubtextAnalysis
+ (instancetype)errorWithMessage:(NSString *)msg {
    WXSubtextAnalysis *a = [[self alloc] init];
    a.ok = NO; a.error = msg ?: @"未知错误";
    return a;
}
+ (instancetype)fromJSONString:(NSString *)json quote:(NSString *)quote {
    if (!json.length) return [self errorWithMessage:@"返回为空"];
    NSString *s = [json stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"```"]) { // 去掉 markdown 代码块包裹
        NSRange l = [s rangeOfString:@"{"], r = [s rangeOfString:@"}" options:NSBackwardsSearch];
        if (l.location != NSNotFound && r.location != NSNotFound && r.location > l.location)
            s = [s substringWithRange:NSMakeRange(l.location, r.location - l.location + 1)];
    }
    // 容错：修复尾随逗号
    s = [[NSRegularExpression regularExpressionWithPattern:@",\\s*\\}" options:0 error:nil]
         stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"}"];
    s = [[NSRegularExpression regularExpressionWithPattern:@",\\s*\\]" options:0 error:nil]
         stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"]"];
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *o = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![o isKindOfClass:[NSDictionary class]]) return [self errorWithMessage:@"返回不是合法 JSON"];
    WXSubtextAnalysis *a = [[self alloc] init];
    a.ok = YES; a.quote = quote;
    a.summary = [o[@"summary"] isKindOfClass:[NSString class]] ? o[@"summary"] : @"";
    a.action = [o[@"action"] isKindOfClass:[NSString class]] ? o[@"action"] : @"";
    a.risk = [o[@"risk"] integerValue];
    NSMutableDictionary *moods = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"开心", @"生气", @"悲伤", @"平淡"])
        moods[k] = @([o[@"moods"][k] integerValue]);
    a.moods = moods;
    NSMutableArray *opts = [NSMutableArray array];
    for (NSDictionary *od in o[@"options"]) {
        if (![od isKindOfClass:[NSDictionary class]]) continue;
        WXSubtextOption *op = [[WXSubtextOption alloc] init];
        op.label = od[@"label"]; op.prob = [od[@"prob"] integerValue];
        op.reason = od[@"reason"]; op.reply = od[@"reply"];
        [opts addObject:op];
    }
    a.options = opts;
    return a;
}
@end
