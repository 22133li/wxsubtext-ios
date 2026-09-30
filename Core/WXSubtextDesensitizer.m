#import "WXSubtextDesensitizer.h"

@implementation WXSubtextDesensitizer

+ (NSArray *)rules {
    static NSArray *r; static dispatch_once_t t;
    dispatch_once(&t, ^{
        NSArray *pairs = @[
            @[@"1[3-9]\\d{9}", @"[手机号]"],
            @[@"\\d{17}[\\dXx]", @"[证件号]"],
            @[@"\\d{16,19}", @"[银行卡]"],
            @[@"\\d+(\\.\\d+)?\\s*(元|块|万|万块|千|k|K)", @"[金额]"],
            @[@"[\\w.+-]+@[\\w-]+\\.[\\w.]+", @"[邮箱]"],
            @[@"https?://\\S+", @"[链接]"],
            @[@"[\u4e00-\u9fa5]{2,8}(路|街|道|巷|小区|花园|大厦|广场|号楼|号院|单元)", @"[地址]"],
            @[@"\\d{1,4}[-/]\\d{1,2}[-/]\\d{1,2}", @"[日期]"],
        ];
        NSMutableArray *out = [NSMutableArray array];
        for (NSArray *p in pairs) {
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:p[0] options:0 error:nil];
            if (re) [out addObject:@[re, p[1]]];
        }
        r = [out copy];
    });
    return r;
}

+ (NSString *)desensitize:(NSString *)text customWords:(NSArray<NSString *> *)words {
    if (!text) return @"";
    NSMutableString *s = [text mutableCopy];
    for (NSArray *rule in [self rules]) {
        NSRegularExpression *re = rule[0];
        [re replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:rule[1]];
    }
    for (NSString *w in words) {
        if (w.length) [s replaceOccurrencesOfString:w withString:@"[隐去]" options:NSLiteralSearch range:NSMakeRange(0, s.length)];
    }
    return s;
}
@end
