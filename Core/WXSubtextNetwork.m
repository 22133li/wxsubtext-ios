#import "WXSubtextNetwork.h"
#import "WXSubtextConfig.h"
#import "WXSubtextPrompt.h"
#import "WXSubtextAnalysis.h"
#import "../Hook/WXSubtextLog.h"

@implementation WXSubtextNetwork
+ (void)analyseWithRelation:(NSString *)relation
                   context:(NSString *)context
                   message:(NSString *)message
                completion:(void(^)(WXSubtextAnalysis *))completion {
    WXSubtextConfig *cfg = [WXSubtextConfig shared];
    if (!cfg.apiKey.length) {
        completion([WXSubtextAnalysis errorWithMessage:@"未配置 API Key（在 com.haoran.wxsubtext.plist 里填 APIKey）"]);
        return;
    }
    NSDictionary *body = @{
        @"model": cfg.model,
        @"messages": @[
            @{@"role": @"system", @"content": [WXSubtextPrompt systemPrompt]},
            @{@"role": @"user", @"content": [WXSubtextPrompt userMessageWithRelation:relation context:context latestMessage:message]},
        ],
        @"temperature": @0.7,
        @"max_tokens": @1200,
        @"response_format": @{@"type": @"json_object"},
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!data) { completion([WXSubtextAnalysis errorWithMessage:@"请求构造失败"]); return; }
    NSURL *url = [NSURL URLWithString:cfg.baseURL];
    if (!url) { completion([WXSubtextAnalysis errorWithMessage:@"BaseURL 非法"]); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:[@"Bearer " stringByAppendingString:[cfg.apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]
        forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = data;
    NSTimeInterval t = MAX(cfg.timeoutMs / 1000.0, 5);
    // 复用 session（连接复用，省掉重复 TLS 握手）
    static NSURLSession *session = nil;
    static dispatch_once_t st;
    dispatch_once(&st, ^{
        NSURLSessionConfiguration *sc = [NSURLSessionConfiguration defaultSessionConfiguration];
        sc.timeoutIntervalForRequest = t; sc.timeoutIntervalForResource = t;
        session = [NSURLSession sessionWithConfiguration:sc];
    });
    [[session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        WXSubtextAnalysis *a = nil;
        if (err) {
            a = [WXSubtextAnalysis errorWithMessage:[@"网络异常：" stringByAppendingString:err.localizedDescription]];
        } else {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            NSString *bodyStr = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
            if (http.statusCode >= 200 && http.statusCode < 300) {
                NSDictionary *o = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                NSArray *choices = o[@"choices"];
                NSString *content = @"";
                if ([choices isKindOfClass:[NSArray class]] && choices.count)
                    content = choices[0][@"message"][@"content"] ?: @"";
                if (!content.length) {
                    // 诊断：把实际返回的前 300 字符记到日志，卡片上也带 80 字符预览，方便定位接口问题
                    NSString *logPreview = bodyStr.length > 300 ? [bodyStr substringToIndex:300] : bodyStr;
                    WXSubtextLogMessage(@"[WXSubtext] API 返回无 choices，HTTP %ld，body 前 300 字符: %@",
                                        (long)http.statusCode, logPreview);
                    NSString *cardPreview = bodyStr.length > 80 ? [bodyStr substringToIndex:80] : bodyStr;
                    a = [WXSubtextAnalysis errorWithMessage:
                         [NSString stringWithFormat:@"返回无 choices（返回内容：%@）", cardPreview]];
                } else {
                    a = [WXSubtextAnalysis fromJSONString:content quote:message];
                }
            } else {
                NSString *head = bodyStr.length > 160 ? [bodyStr substringToIndex:160] : bodyStr;
                a = [WXSubtextAnalysis errorWithMessage:[NSString stringWithFormat:@"HTTP %ld %@", (long)http.statusCode, head]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(a); });
    }] resume];
}
@end
