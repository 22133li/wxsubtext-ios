#import "WXSubtextCardView.h"
#import "WXSubtextAnalysis.h"
#import <objc/runtime.h>

@implementation WXSubtextCardView {
    UIStackView *_stack;
    UIActivityIndicatorView *_spinner;
    UILabel *_statusLabel;
    UIButton *_retryBtn;
    WXSubtextAnalysis *_analysis;
}

- (instancetype)initWithFrame:(CGRect)f {
    if (self = [super initWithFrame:f]) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 6;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:10].active = YES;
        [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10].active = YES;
        [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10].active = YES;
        [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10].active = YES;
        // 顶部栏
        UIView *head = [[UIView alloc] init];
        UILabel *t = [[UILabel alloc] init];
        t.text = @"潜台词"; t.font = [UIFont boldSystemFontOfSize:13];
        t.textColor = [UIColor colorWithRed:1 green:0.85 blue:0.4 alpha:1];
        [head addSubview:t]; t.translatesAutoresizingMaskIntoConstraints = NO;
        [t.leadingAnchor constraintEqualToAnchor:head.leadingAnchor].active = YES;
        [t.centerYAnchor constraintEqualToAnchor:head.centerYAnchor].active = YES;
        UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
        [x setTitle:@"✕" forState:UIControlStateNormal];
        x.titleLabel.font = [UIFont systemFontOfSize:13];
        [x setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
        [x addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [head addSubview:x]; x.translatesAutoresizingMaskIntoConstraints = NO;
        [x.trailingAnchor constraintEqualToAnchor:head.trailingAnchor].active = YES;
        [x.centerYAnchor constraintEqualToAnchor:head.centerYAnchor].active = YES;
        [head.heightAnchor constraintEqualToConstant:20].active = YES;
        [_stack addArrangedSubview:head];
    }
    return self;
}
- (void)closeTapped { if (self.onClose) self.onClose(); [self removeFromSuperview]; }

- (void)clearBody {
    for (UIView *v in [_stack.arrangedSubviews subarrayWithRange:NSMakeRange(1, _stack.arrangedSubviews.count - 1)])
        [_stack removeArrangedSubview:v], [v removeFromSuperview];
    _spinner = nil; _statusLabel = nil; _retryBtn = nil;
}
- (UILabel *)label:(NSString *)text size:(CGFloat)s color:(UIColor *)c bold:(BOOL)b {
    UILabel *l = [[UILabel alloc] init];
    l.text = text; l.numberOfLines = 0;
    l.font = b ? [UIFont boldSystemFontOfSize:s] : [UIFont systemFontOfSize:s];
    l.textColor = c ?: [UIColor whiteColor];
    return l;
}

- (void)showLoading {
    [self clearBody];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [UIColor whiteColor];
    [_spinner startAnimating];
    UIView *row = [[UIView alloc] init];
    [row addSubview:_spinner]; _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_spinner.centerXAnchor constraintEqualToAnchor:row.centerXAnchor].active = YES;
    [_spinner.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [row.heightAnchor constraintEqualToConstant:44].active = YES;
    [_stack addArrangedSubview:row];
    [_stack addArrangedSubview:[self label:@"正在解读潜台词…" size:12 color:[UIColor lightGrayColor] bold:NO]];
}

- (void)showError:(NSString *)message {
    [self clearBody];
    [_stack addArrangedSubview:[self label:message ?: @"分析失败" size:12 color:[UIColor colorWithRed:1 green:0.5 blue:0.5 alpha:1] bold:NO]];
    _retryBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_retryBtn setTitle:@"重试" forState:UIControlStateNormal];
    _retryBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [_retryBtn addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:_retryBtn];
}
- (void)retryTapped { if (self.onRetry) self.onRetry(); }

// 心情条：单行 [名称 彩色条 百分比]
- (UIView *)moodRow:(NSString *)name value:(NSInteger)v color:(UIColor *)c maxW:(CGFloat)maxW {
    UIView *row = [[UIView alloc] init];
    UILabel *n = [self label:name size:11 color:[UIColor lightGrayColor] bold:NO];
    n.frame = CGRectMake(0, 0, 34, 16);
    UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(38, 3, maxW, 10)];
    bg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    bg.layer.cornerRadius = 5;
    UIView *fg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(4, maxW * v / 100.0), 10)];
    fg.backgroundColor = c; fg.layer.cornerRadius = 5;
    [bg addSubview:fg];
    UILabel *p = [self label:[NSString stringWithFormat:@"%ld%%", (long)v] size:11 color:[UIColor lightGrayColor] bold:NO];
    p.frame = CGRectMake(42 + maxW, 0, 40, 16);
    [row addSubview:n]; [row addSubview:bg]; [row addSubview:p];
    row.frame = CGRectMake(0, 0, 82 + maxW, 16);
    [row.heightAnchor constraintEqualToConstant:16].active = YES;
    return row;
}

- (void)showAnalysis:(WXSubtextAnalysis *)a collapseTop1:(BOOL)collapse {
    [self clearBody];
    if (!a.ok) { [self showError:a.error]; return; }
    _analysis = a;
    [_stack addArrangedSubview:[self label:a.summary size:13 color:[UIColor whiteColor] bold:YES]];
    // 心情指数
    NSArray *keys = @[@"开心", @"生气", @"悲伤", @"平淡"];
    NSArray *colors = @[[UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1],
                        [UIColor colorWithRed:1 green:0.35 blue:0.35 alpha:1],
                        [UIColor colorWithRed:0.4 green:0.6 blue:1 alpha:1],
                        [UIColor colorWithWhite:0.7 alpha:1]];
    for (NSInteger i = 0; i < 4; i++)
        [_stack addArrangedSubview:[self moodRow:keys[i] value:[a.moods[keys[i]] integerValue] color:colors[i] maxW:100]];
    UIColor *riskC = a.risk >= 7 ? [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1] : [UIColor lightGrayColor];
    [_stack addArrangedSubview:[self label:[NSString stringWithFormat:@"风险等级：%ld/10", (long)a.risk] size:12 color:riskC bold:NO]];
    // 解读选项
    NSInteger idx = 0;
    for (WXSubtextOption *op in a.options) {
        BOOL expanded = !collapse || idx == 0;
        UIView *box = [[UIView alloc] init];
        box.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        box.layer.cornerRadius = 8;
        UIStackView *bs = [[UIStackView alloc] init];
        bs.axis = UILayoutConstraintAxisVertical; bs.spacing = 4;
        bs.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:bs];
        [bs.topAnchor constraintEqualToAnchor:box.topAnchor constant:8].active = YES;
        [bs.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8].active = YES;
        [bs.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8].active = YES;
        [bs.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8].active = YES;
        NSString *title = [NSString stringWithFormat:@"%@  %ld%%", op.label ?: @"", (long)op.prob];
        [bs addArrangedSubview:[self label:title size:13 color:[UIColor colorWithRed:1 green:0.85 blue:0.4 alpha:1] bold:YES]];
        if (expanded) {
            if (op.reason.length) [bs addArrangedSubview:[self label:op.reason size:11 color:[UIColor colorWithWhite:0.75 alpha:1] bold:NO]];
            if (op.reply.length) {
                UIView *rrow = [[UIView alloc] init];
                UILabel *rl = [self label:[NSString stringWithFormat:@"“%@”", op.reply] size:12 color:[UIColor whiteColor] bold:NO];
                rl.translatesAutoresizingMaskIntoConstraints = NO;
                UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
                [cp setTitle:@"复制" forState:UIControlStateNormal];
                cp.titleLabel.font = [UIFont systemFontOfSize:12];
                cp.tag = idx; // 用 tag 找回 reply
                [cp addTarget:self action:@selector(copyTapped:) forControlEvents:UIControlEventTouchUpInside];
                objc_setAssociatedObject(cp, @"reply", op.reply, OBJC_ASSOCIATION_COPY_NONATOMIC);
                [rrow addSubview:rl]; [rrow addSubview:cp];
                cp.translatesAutoresizingMaskIntoConstraints = NO;
                [rl.leadingAnchor constraintEqualToAnchor:rrow.leadingAnchor].active = YES;
                [rl.centerYAnchor constraintEqualToAnchor:rrow.centerYAnchor].active = YES;
                [rl.trailingAnchor constraintLessThanOrEqualToAnchor:cp.leadingAnchor constant:-6].active = YES;
                [cp.trailingAnchor constraintEqualToAnchor:rrow.trailingAnchor].active = YES;
                [cp.centerYAnchor constraintEqualToAnchor:rrow.centerYAnchor].active = YES;
                [rrow.heightAnchor constraintEqualToConstant:24].active = YES;
                [bs addArrangedSubview:rrow];
            }
        } else {
            // 折叠态：点击展开
            UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
            [more setTitle:@"展开解读 ▾" forState:UIControlStateNormal];
            more.titleLabel.font = [UIFont systemFontOfSize:11];
            objc_setAssociatedObject(more, @"option", op, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [more addTarget:self action:@selector(expandTapped:) forControlEvents:UIControlEventTouchUpInside];
            [bs addArrangedSubview:more];
        }
        [_stack addArrangedSubview:box];
        idx++;
    }
    if (a.action.length)
        [_stack addArrangedSubview:[self label:[NSString stringWithFormat:@"建议：%@", a.action] size:12 color:[UIColor colorWithRed:0.6 green:1 blue:0.6 alpha:1] bold:NO]];
}
- (void)copyTapped:(UIButton *)b {
    NSString *reply = objc_getAssociatedObject(b, @"reply");
    if (reply.length) {
        [UIPasteboard generalPasteboard].string = reply;
        [b setTitle:@"已复制" forState:UIControlStateNormal];
    }
}
- (void)expandTapped:(UIButton *)b {
    if (_analysis) [self showAnalysis:_analysis collapseTop1:NO]; // 展开全部四条
}
@end
