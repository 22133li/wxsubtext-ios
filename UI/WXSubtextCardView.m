#import "WXSubtextCardView.h"
#import "WXSubtextAnalysis.h"
#import <objc/runtime.h>

@implementation WXSubtextCardView {
    UIStackView *_stack;
    UIActivityIndicatorView *_spinner;
    WXSubtextAnalysis *_analysis;
}

- (instancetype)initWithFrame:(CGRect)f {
    if (self = [super initWithFrame:f]) {
        // 深色磨砂质感 + 阴影
        self.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.16 alpha:0.97];
        self.layer.cornerRadius = 14;
        self.layer.masksToBounds = NO;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        // 顶部微光边
        UIView *topGlow = [[UIView alloc] init];
        topGlow.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        topGlow.layer.cornerRadius = 14;
        topGlow.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        topGlow.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:topGlow];
        [topGlow.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
        [topGlow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
        [topGlow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
        [topGlow.heightAnchor constraintEqualToConstant:1.5].active = YES;

        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 8;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12].active = YES;
        [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12].active = YES;
        [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14].active = YES;
        [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14].active = YES;
        // 顶部栏：✨ 潜台词 + 关闭
        UIView *head = [[UIView alloc] init];
        UILabel *t = [[UILabel alloc] init];
        t.text = @"✨ 潜台词";
        t.font = [UIFont boldSystemFontOfSize:14];
        t.textColor = [UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:1];
        [head addSubview:t]; t.translatesAutoresizingMaskIntoConstraints = NO;
        [t.leadingAnchor constraintEqualToAnchor:head.leadingAnchor].active = YES;
        [t.centerYAnchor constraintEqualToAnchor:head.centerYAnchor].active = YES;
        UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
        [x setTitle:@"✕" forState:UIControlStateNormal];
        x.titleLabel.font = [UIFont systemFontOfSize:14];
        [x setTitleColor:[UIColor colorWithWhite:0.6 alpha:1] forState:UIControlStateNormal];
        x.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        x.layer.cornerRadius = 11;
        x.clipsToBounds = YES;
        [x addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [head addSubview:x]; x.translatesAutoresizingMaskIntoConstraints = NO;
        [x.trailingAnchor constraintEqualToAnchor:head.trailingAnchor].active = YES;
        [x.centerYAnchor constraintEqualToAnchor:head.centerYAnchor].active = YES;
        [x.widthAnchor constraintEqualToConstant:22].active = YES;
        [x.heightAnchor constraintEqualToConstant:22].active = YES;
        [head.heightAnchor constraintEqualToConstant:22].active = YES;
        [_stack addArrangedSubview:head];
        // 分隔线
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        [sep.heightAnchor constraintEqualToConstant:0.5].active = YES;
        [_stack addArrangedSubview:sep];
    }
    return self;
}
- (void)closeTapped { if (self.onClose) self.onClose(); [self removeFromSuperview]; }

- (void)setMaxLayoutWidth:(CGFloat)w forView:(UIView *)v {
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        if (l.numberOfLines != 1) l.preferredMaxLayoutWidth = w;
    }
    for (UIView *s in v.subviews) [self setMaxLayoutWidth:w forView:s];
}
- (void)fitHeight {
    CGFloat w = self.frame.size.width - 28;
    [self setMaxLayoutWidth:w forView:_stack];
    CGSize fitting = [_stack systemLayoutSizeFittingSize:CGSizeMake(w, 0)
                                withHorizontalFittingPriority:UILayoutPriorityRequired
                                      verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect f = self.frame;
    f.size.height = MAX(76, fitting.height + 24);
    self.frame = f;
    // 阴影路径跟随圆角，避免离屏渲染
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:14].CGPath;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:14].CGPath;
}

- (void)clearBody {
    // 保留 header(0) 与分隔线(1)
    while (_stack.arrangedSubviews.count > 2) {
        UIView *v = _stack.arrangedSubviews.lastObject;
        [_stack removeArrangedSubview:v]; [v removeFromSuperview];
    }
    _spinner = nil;
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
    UIView *row = [[UIView alloc] init];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:1];
    [_spinner startAnimating];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *t = [self label:@"正在解读潜台词…" size:12 color:[UIColor colorWithWhite:0.65 alpha:1] bold:NO];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:_spinner]; [row addSubview:t];
    [_spinner.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [_spinner.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [t.leadingAnchor constraintEqualToAnchor:_spinner.trailingAnchor constant:8].active = YES;
    [t.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [row.heightAnchor constraintEqualToConstant:36].active = YES;
    [_stack addArrangedSubview:row];
    [self fitHeight];
}

- (void)showError:(NSString *)message {
    [self clearBody];
    UIView *row = [[UIView alloc] init];
    UILabel *icon = [self label:@"⚠️" size:14 color:nil bold:NO];
    UILabel *msg = [self label:message ?: @"分析失败" size:12 color:[UIColor colorWithRed:1 green:0.55 blue:0.55 alpha:1] bold:NO];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    msg.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:icon]; [row addSubview:msg];
    [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [icon.topAnchor constraintEqualToAnchor:row.topAnchor].active = YES;
    [msg.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6].active = YES;
    [msg.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    [msg.topAnchor constraintEqualToAnchor:row.topAnchor].active = YES;
    [msg.bottomAnchor constraintEqualToAnchor:row.bottomAnchor].active = YES;
    [_stack addArrangedSubview:row];
    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:@"↻ 重试" forState:UIControlStateNormal];
    retry.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [retry setTitleColor:[UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:1] forState:UIControlStateNormal];
    retry.backgroundColor = [UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:0.12];
    retry.layer.cornerRadius = 8;
    retry.clipsToBounds = YES;
    [retry addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    [retry.heightAnchor constraintEqualToConstant:34].active = YES;
    [_stack addArrangedSubview:retry];
    [self fitHeight];
}
- (void)retryTapped { if (self.onRetry) self.onRetry(); }

// 心情条：😊 名称 ━━━━━━ 42%
- (UIView *)moodRow:(NSString *)emoji name:(NSString *)name value:(NSInteger)v color:(UIColor *)c maxW:(CGFloat)maxW {
    UIView *row = [[UIView alloc] init];
    UILabel *e = [self label:emoji size:12 color:nil bold:NO];
    e.frame = CGRectMake(0, 0, 20, 16);
    UILabel *n = [self label:name size:11 color:[UIColor colorWithWhite:0.6 alpha:1] bold:NO];
    n.frame = CGRectMake(20, 0, 30, 16);
    UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(52, 4, maxW, 8)];
    bg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    bg.layer.cornerRadius = 4;
    CGFloat fw = MAX(6, maxW * MIN(v, 100) / 100.0);
    UIView *fg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, fw, 8)];
    fg.backgroundColor = c; fg.layer.cornerRadius = 4;
    [bg addSubview:fg];
    UILabel *p = [self label:[NSString stringWithFormat:@"%ld%%", (long)v] size:11 color:[UIColor whiteColor] bold:YES];
    p.frame = CGRectMake(56 + maxW, 0, 42, 16);
    [row addSubview:e]; [row addSubview:n]; [row addSubview:bg]; [row addSubview:p];
    [row.heightAnchor constraintEqualToConstant:16].active = YES;
    return row;
}

// 风险徽章：圆角小 pill，颜色随等级
- (UIView *)riskBadge:(NSInteger)risk {
    UIColor *c = risk >= 7 ? [UIColor colorWithRed:1 green:0.38 blue:0.38 alpha:1]
               : risk >= 4 ? [UIColor colorWithRed:1 green:0.72 blue:0.25 alpha:1]
               : [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1];
    NSString *txt = risk >= 7 ? @"高风险" : risk >= 4 ? @"中等风险" : @"低风险";
    UIView *row = [[UIView alloc] init];
    UILabel *cap = [self label:@"风险" size:11 color:[UIColor colorWithWhite:0.6 alpha:1] bold:NO];
    cap.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *pill = [[UIView alloc] init];
    pill.backgroundColor = [c colorWithAlphaComponent:0.16];
    pill.layer.cornerRadius = 9;
    pill.clipsToBounds = YES;
    UILabel *pl = [self label:[NSString stringWithFormat:@"%@ %ld/10", txt, (long)risk] size:11 color:c bold:YES];
    pl.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:pl];
    [pl.topAnchor constraintEqualToAnchor:pill.topAnchor constant:3].active = YES;
    [pl.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-3].active = YES;
    [pl.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10].active = YES;
    [pl.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10].active = YES;
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:cap]; [row addSubview:pill];
    [cap.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [cap.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [pill.leadingAnchor constraintEqualToAnchor:cap.trailingAnchor constant:8].active = YES;
    [pill.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [row.heightAnchor constraintEqualToConstant:20].active = YES;
    return row;
}

- (void)showAnalysis:(WXSubtextAnalysis *)a collapseTop1:(BOOL)collapse {
    [self clearBody];
    if (!a.ok) { [self showError:a.error]; return; }
    _analysis = a;
    // 总结
    [_stack addArrangedSubview:[self label:a.summary size:14 color:[UIColor whiteColor] bold:YES]];
    // 心情指数
    NSArray *emojis = @[@"😊", @"😠", @"😢", @"😐"];
    NSArray *keys = @[@"开心", @"生气", @"悲伤", @"平淡"];
    NSArray *colors = @[[UIColor colorWithRed:1 green:0.78 blue:0.25 alpha:1],
                        [UIColor colorWithRed:1 green:0.38 blue:0.38 alpha:1],
                        [UIColor colorWithRed:0.42 green:0.62 blue:1 alpha:1],
                        [UIColor colorWithWhite:0.65 alpha:1]];
    for (NSInteger i = 0; i < 4; i++)
        [_stack addArrangedSubview:[self moodRow:emojis[i] name:keys[i]
                                          value:[a.moods[keys[i]] integerValue] color:colors[i] maxW:110]];
    [_stack addArrangedSubview:[self riskBadge:a.risk]];
    // 解读选项
    NSInteger idx = 0;
    for (WXSubtextOption *op in a.options) {
        BOOL expanded = !collapse || idx == 0;
        UIView *box = [[UIView alloc] init];
        box.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
        box.layer.cornerRadius = 10;
        box.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.06].CGColor;
        box.layer.borderWidth = 0.5;
        UIStackView *bs = [[UIStackView alloc] init];
        bs.axis = UILayoutConstraintAxisVertical; bs.spacing = 6;
        bs.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:bs];
        [bs.topAnchor constraintEqualToAnchor:box.topAnchor constant:10].active = YES;
        [bs.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10].active = YES;
        [bs.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:10].active = YES;
        [bs.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-10].active = YES;
        // 标题行：解读名 + 概率徽章
        UIView *trow = [[UIView alloc] init];
        UILabel *tl = [self label:op.label ?: @"" size:13 color:[UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:1] bold:YES];
        tl.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *prob = [[UIView alloc] init];
        prob.backgroundColor = [UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:0.14];
        prob.layer.cornerRadius = 8;
        prob.clipsToBounds = YES;
        UILabel *pl = [self label:[NSString stringWithFormat:@"%ld%%", (long)op.prob] size:11
                            color:[UIColor colorWithRed:1 green:0.84 blue:0.38 alpha:1] bold:YES];
        pl.translatesAutoresizingMaskIntoConstraints = NO;
        [prob addSubview:pl];
        [pl.topAnchor constraintEqualToAnchor:prob.topAnchor constant:2].active = YES;
        [pl.bottomAnchor constraintEqualToAnchor:prob.bottomAnchor constant:-2].active = YES;
        [pl.leadingAnchor constraintEqualToAnchor:prob.leadingAnchor constant:8].active = YES;
        [pl.trailingAnchor constraintEqualToAnchor:prob.trailingAnchor constant:-8].active = YES;
        prob.translatesAutoresizingMaskIntoConstraints = NO;
        [trow addSubview:tl]; [trow addSubview:prob];
        [tl.leadingAnchor constraintEqualToAnchor:trow.leadingAnchor].active = YES;
        [tl.centerYAnchor constraintEqualToAnchor:trow.centerYAnchor].active = YES;
        [prob.trailingAnchor constraintEqualToAnchor:trow.trailingAnchor].active = YES;
        [prob.centerYAnchor constraintEqualToAnchor:trow.centerYAnchor].active = YES;
        [trow.heightAnchor constraintEqualToConstant:20].active = YES;
        [bs addArrangedSubview:trow];
        if (expanded) {
            if (op.reason.length)
                [bs addArrangedSubview:[self label:op.reason size:11 color:[UIColor colorWithWhite:0.72 alpha:1] bold:NO]];
            if (op.reply.length) {
                UIView *rbox = [[UIView alloc] init];
                rbox.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
                rbox.layer.cornerRadius = 8;
                UILabel *rl = [self label:[NSString stringWithFormat:@"“%@”", op.reply] size:12 color:[UIColor whiteColor] bold:NO];
                rl.translatesAutoresizingMaskIntoConstraints = NO;
                UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
                [cp setTitle:@"复制" forState:UIControlStateNormal];
                cp.titleLabel.font = [UIFont boldSystemFontOfSize:11];
                [cp setTitleColor:[UIColor colorWithRed:0.45 green:0.75 blue:1 alpha:1] forState:UIControlStateNormal];
                cp.backgroundColor = [UIColor colorWithRed:0.45 green:0.75 blue:1 alpha:0.12];
                cp.layer.cornerRadius = 6;
                cp.clipsToBounds = YES;
                [cp setContentEdgeInsets:UIEdgeInsetsMake(4, 10, 4, 10)];
                objc_setAssociatedObject(cp, @"reply", op.reply, OBJC_ASSOCIATION_COPY_NONATOMIC);
                [cp addTarget:self action:@selector(copyTapped:) forControlEvents:UIControlEventTouchUpInside];
                cp.translatesAutoresizingMaskIntoConstraints = NO;
                [rbox addSubview:rl]; [rbox addSubview:cp];
                [rl.leadingAnchor constraintEqualToAnchor:rbox.leadingAnchor constant:8].active = YES;
                [rl.topAnchor constraintEqualToAnchor:rbox.topAnchor constant:6].active = YES;
                [rl.bottomAnchor constraintEqualToAnchor:rbox.bottomAnchor constant:-6].active = YES;
                [rl.trailingAnchor constraintLessThanOrEqualToAnchor:cp.leadingAnchor constant:-8].active = YES;
                [cp.trailingAnchor constraintEqualToAnchor:rbox.trailingAnchor constant:-8].active = YES;
                [cp.centerYAnchor constraintEqualToAnchor:rbox.centerYAnchor].active = YES;
                [bs addArrangedSubview:rbox];
            }
        } else {
            UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
            [more setTitle:@"展开解读 ▾" forState:UIControlStateNormal];
            more.titleLabel.font = [UIFont systemFontOfSize:11];
            [more setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
            objc_setAssociatedObject(more, @"option", op, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [more addTarget:self action:@selector(expandTapped:) forControlEvents:UIControlEventTouchUpInside];
            [bs addArrangedSubview:more];
        }
        [_stack addArrangedSubview:box];
        idx++;
    }
    if (a.action.length) {
        UIView *arow = [[UIView alloc] init];
        UILabel *icon = [self label:@"💡" size:13 color:nil bold:NO];
        UILabel *al = [self label:a.action size:12 color:[UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1] bold:NO];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        al.translatesAutoresizingMaskIntoConstraints = NO;
        [arow addSubview:icon]; [arow addSubview:al];
        [icon.leadingAnchor constraintEqualToAnchor:arow.leadingAnchor].active = YES;
        [icon.topAnchor constraintEqualToAnchor:arow.topAnchor].active = YES;
        [al.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6].active = YES;
        [al.trailingAnchor constraintEqualToAnchor:arow.trailingAnchor].active = YES;
        [al.topAnchor constraintEqualToAnchor:arow.topAnchor].active = YES;
        [al.bottomAnchor constraintEqualToAnchor:arow.bottomAnchor].active = YES;
        [_stack addArrangedSubview:arow];
    }
    [self fitHeight];
}
- (void)copyTapped:(UIButton *)b {
    NSString *reply = objc_getAssociatedObject(b, @"reply");
    if (reply.length) {
        [UIPasteboard generalPasteboard].string = reply;
        [b setTitle:@"已复制 ✓" forState:UIControlStateNormal];
    }
}
- (void)expandTapped:(UIButton *)b {
    if (_analysis) [self showAnalysis:_analysis collapseTop1:NO];
}
@end
