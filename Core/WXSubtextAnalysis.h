#import <Foundation/Foundation.h>

// 单条解读选项：label（心理状态命名，<=6字）/prob（整数概率）/reason（依据）/reply（可直接发送的回复）
@interface WXSubtextOption : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) NSInteger prob;
@property (nonatomic, copy) NSString *reason;
@property (nonatomic, copy) NSString *reply;
@end

// AI 返回的分析结果，与 Android 版 Analysis 字段一致
@interface WXSubtextAnalysis : NSObject
@property (nonatomic, assign) BOOL ok;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *moods; // 开心/生气/悲伤/平淡 -> 0-100
@property (nonatomic, assign) NSInteger risk;   // 0-10
@property (nonatomic, copy) NSString *action;   // 最佳行动建议
@property (nonatomic, copy) NSArray<WXSubtextOption *> *options; // 4 项
@property (nonatomic, copy) NSString *quote;    // 关联的消息原文
@property (nonatomic, copy) NSString *error;    // ok=NO 时的错误描述
+ (instancetype)fromJSONString:(NSString *)json quote:(NSString *)quote;
+ (instancetype)errorWithMessage:(NSString *)msg;
@end
