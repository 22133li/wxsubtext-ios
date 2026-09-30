#import "WXSubtextSettingsVC.h"
#import "../Core/WXSubtextConfig.h"

typedef NS_ENUM(NSInteger, WXRowType) {
    WXRowSwitch = 0,  // UISwitch
    WXRowText,        // 普通文本
    WXRowSecure,      // 密码文本（API Key）
    WXRowNumber,      // 数字
    WXRowMemo,        // 多行文本（一行一个）
};

@implementation WXSubtextSettingsVC {
    NSArray *_sections;
}

- (instancetype)init {
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
        self.title = @"潜台词";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"潜台词";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _sections = @[
        @{@"title": @"", @"footer": @"修改实时生效，无需重启微信", @"rows": @[
            @{@"type": @(WXRowSwitch), @"key": @"Enabled", @"title": @"启用分析"},
        ]},
        @{@"title": @"接口配置", @"rows": @[
            @{@"type": @(WXRowSecure), @"key": @"APIKey", @"title": @"API Key", @"placeholder": @"sk-..."},
            @{@"type": @(WXRowText), @"key": @"BaseURL", @"title": @"接口地址", @"placeholder": @"https://..."},
            @{@"type": @(WXRowText), @"key": @"Model", @"title": @"模型", @"placeholder": @"deepseek-chat"},
        ]},
        @{@"title": @"分析设置", @"rows": @[
            @{@"type": @(WXRowText), @"key": @"RelationDefault", @"title": @"默认关系", @"placeholder": @"亲密关系（伴侣）"},
            @{@"type": @(WXRowSwitch), @"key": @"Desensitize", @"title": @"上传前脱敏"},
            @{@"type": @(WXRowSwitch), @"key": @"AnalyzeAllContacts", @"title": @"分析所有单聊"},
            @{@"type": @(WXRowSwitch), @"key": @"CollapseToTop1", @"title": @"卡片默认折叠"},
            @{@"type": @(WXRowSwitch), @"key": @"OnlyLatest", @"title": @"只分析最新消息"},
        ]},
        @{@"title": @"白名单", @"footer": @"每行一个微信备注名；「分析所有单聊」打开时此名单无效", @"rows": @[
            @{@"type": @(WXRowMemo), @"key": @"EnabledTalkers"},
        ]},
        @{@"title": @"自定义敏感词", @"footer": @"每行一个，命中后替换为 [敏感词]", @"rows": @[
            @{@"type": @(WXRowMemo), @"key": @"SensitiveWords"},
        ]},
        @{@"title": @"限流", @"rows": @[
            @{@"type": @(WXRowNumber), @"key": @"MaxCallsPerHour", @"title": @"每小时上限", @"placeholder": @"60"},
            @{@"type": @(WXRowNumber), @"key": @"ContextSize", @"title": @"上下文条数", @"placeholder": @"5"},
            @{@"type": @(WXRowNumber), @"key": @"TimeoutMs", @"title": @"超时(ms)", @"placeholder": @"30000"},
        ]},
    ];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - 取值 / 落盘

- (id)valueForRowKey:(NSString *)key {
    WXSubtextConfig *c = [WXSubtextConfig shared];
    if ([key isEqualToString:@"Enabled"]) return @(c.enabled);
    if ([key isEqualToString:@"AnalyzeAllContacts"]) return @(c.analyzeAllContacts);
    if ([key isEqualToString:@"APIKey"]) return c.apiKey ?: @"";
    if ([key isEqualToString:@"BaseURL"]) return c.baseURL ?: @"";
    if ([key isEqualToString:@"Model"]) return c.model ?: @"";
    if ([key isEqualToString:@"RelationDefault"]) return c.relationDefault ?: @"";
    if ([key isEqualToString:@"Desensitize"]) return @(c.desensitize);
    if ([key isEqualToString:@"CollapseToTop1"]) return @(c.collapseToTop1);
    if ([key isEqualToString:@"OnlyLatest"]) return @(c.onlyLatest);
    if ([key isEqualToString:@"MaxCallsPerHour"]) return @(c.maxCallsPerHour);
    if ([key isEqualToString:@"ContextSize"]) return @(c.contextSize);
    if ([key isEqualToString:@"TimeoutMs"]) return @(c.timeoutMs);
    if ([key isEqualToString:@"EnabledTalkers"])
        return [[c.enabledTalkers allObjects] sortedArrayUsingSelector:@selector(compare:)];
    if ([key isEqualToString:@"SensitiveWords"]) return c.sensitiveWords ?: @[];
    return nil;
}

- (void)writeValue:(id)v forKey:(NSString *)key type:(WXRowType)type {
    WXSubtextConfig *c = [WXSubtextConfig shared];
    if (type == WXRowSwitch)      [c writeBool:[v boolValue] forKey:key];
    else if (type == WXRowNumber) [c writeInteger:[v integerValue] forKey:key];
    else if (type == WXRowMemo)   [c writeArray:v forKey:key];
    else                         [c writeString:v forKey:key];
}

- (NSDictionary *)rowAt:(NSIndexPath *)ip {
    return _sections[ip.section][@"rows"][ip.row];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return [_sections[s][@"rows"] count];
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    NSString *t = _sections[s][@"title"];
    return t.length ? t : nil;
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    NSString *t = _sections[s][@"footer"];
    return t.length ? t : nil;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *row = [self rowAt:ip];
    return [row[@"type"] integerValue] == WXRowMemo ? 120 : 48;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *row = [self rowAt:ip];
    WXRowType type = [row[@"type"] integerValue];
    NSString *key = row[@"key"];
    id val = [self valueForRowKey:key];
    NSInteger tag = ip.section * 1000 + ip.row;

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (type == WXRowSwitch) {
        cell.textLabel.text = row[@"title"];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [val boolValue];
        sw.tag = tag;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }
    if (type == WXRowMemo) {
        UITextView *tev = [[UITextView alloc] init];
        tev.translatesAutoresizingMaskIntoConstraints = NO;
        tev.font = [UIFont systemFontOfSize:15];
        tev.tag = tag;
        tev.delegate = (id<UITextViewDelegate>)self;
        if ([val isKindOfClass:[NSArray class]])
            tev.text = [(NSArray *)val componentsJoinedByString:@"\n"];
        [cell.contentView addSubview:tev];
        [tev.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8].active = YES;
        [tev.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8].active = YES;
        [tev.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12].active = YES;
        [tev.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12].active = YES;
        return cell;
    }
    // 文本 / 密码 / 数字
    cell.textLabel.text = row[@"title"];
    UITextField *tf = [[UITextField alloc] init];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.textAlignment = NSTextAlignmentRight;
    tf.font = [UIFont systemFontOfSize:15];
    tf.textColor = [UIColor grayColor];
    tf.placeholder = row[@"placeholder"];
    tf.tag = tag;
    tf.delegate = (id<UITextFieldDelegate>)self;
    tf.returnKeyType = UIReturnKeyDone;
    if (type == WXRowSecure) tf.secureTextEntry = YES;
    if (type == WXRowNumber) tf.keyboardType = UIKeyboardTypeNumberPad;
    if ([val isKindOfClass:[NSString class]]) tf.text = val;
    else if ([val isKindOfClass:[NSNumber class]]) tf.text = [val stringValue];
    [cell.contentView addSubview:tf];
    [tf.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:150].active = YES;
    [tf.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16].active = YES;
    [tf.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor].active = YES;
    [tf.heightAnchor constraintEqualToConstant:32].active = YES;
    return cell;
}

#pragma mark - 事件

- (void)switchChanged:(UISwitch *)sw {
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag % 1000 inSection:sw.tag / 1000];
    NSDictionary *row = [self rowAt:ip];
    [self writeValue:@(sw.isOn) forKey:row[@"key"] type:WXRowSwitch];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)tf {
    NSIndexPath *ip = [NSIndexPath indexPathForRow:tf.tag % 1000 inSection:tf.tag / 1000];
    NSDictionary *row = [self rowAt:ip];
    WXRowType type = [row[@"type"] integerValue];
    NSString *text = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (type == WXRowNumber) {
        // 非数字则恢复原值
        NSCharacterSet *bad = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if (text.length && [text rangeOfCharacterFromSet:bad].location != NSNotFound) {
            tf.text = [[self valueForRowKey:row[@"key"]] stringValue];
            return;
        }
        if (!text.length) text = @"0";
    }
    [self writeValue:text forKey:row[@"key"] type:type];
}

- (void)textViewDidEndEditing:(UITextView *)tv {
    NSIndexPath *ip = [NSIndexPath indexPathForRow:tv.tag % 1000 inSection:tv.tag / 1000];
    NSDictionary *row = [self rowAt:ip];
    NSMutableArray *lines = [NSMutableArray array];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *ln in [tv.text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [ln stringByTrimmingCharactersInSet:ws];
        if (t.length) [lines addObject:t];
    }
    [self writeValue:lines forKey:row[@"key"] type:WXRowMemo];
}

@end
