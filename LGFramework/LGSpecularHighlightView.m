#import "LGSpecularHighlightView.h"

@interface LGSpecularHighlightView ()
@property (nonatomic, strong) CAGradientLayer *fresnelGlare;
@property (nonatomic, strong) CAGradientLayer *specularRim;
@property (nonatomic, strong) CAShapeLayer *rimMask;
@property (nonatomic, strong) CAGradientLayer *darkEdgeRim;
@property (nonatomic, strong) CAShapeLayer *darkEdgeMask;
@end

@implementation LGSpecularHighlightView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame cornerRadius:40.0];
}

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius {
    self = [super initWithFrame:frame];
    if (self) {
        _cornerRadius = cornerRadius;
        _strokeWidth = 0.50;
        _topSpecularOpacity = 0.60;
        _bottomSpecularOpacity = 0.30;

        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];

        // 1. Fresnel Glare: Soft inward diffusion along top & bottom rims
        CGFloat glareAlpha = _topSpecularOpacity * 0.26;
        self.fresnelGlare = [CAGradientLayer layer];
        self.fresnelGlare.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha * 0.55].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha * 0.22].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha * 0.06].CGColor,
            (id)UIColor.clearColor.CGColor,
            (id)UIColor.clearColor.CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha * 0.06].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha * 0.22].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha * 0.55].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glareAlpha].CGColor
        ];
        self.fresnelGlare.locations = @[
            @0.0, @0.035, @0.09, @0.18, @0.28,
            @0.72, @0.82, @0.91, @0.965, @1.0
        ];
        self.fresnelGlare.startPoint = CGPointMake(0.5, 0.0);
        self.fresnelGlare.endPoint = CGPointMake(0.5, 1.0);
        [self.layer addSublayer:self.fresnelGlare];

        // 2. Dark Edge Rim: Outer boundary stroke along exterior perimeter
        self.darkEdgeRim = [CAGradientLayer layer];
        self.darkEdgeRim.colors = @[
            (id)[UIColor colorWithWhite:0.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.48].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.48].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.28].CGColor
        ];
        self.darkEdgeRim.locations = @[@0.0, @0.15, @0.30, @0.70, @0.85, @1.0];
        self.darkEdgeRim.startPoint = CGPointMake(0.5, 0.0);
        self.darkEdgeRim.endPoint = CGPointMake(0.5, 1.0);

        self.darkEdgeMask = [CAShapeLayer layer];
        self.darkEdgeMask.fillColor = [UIColor clearColor].CGColor;
        self.darkEdgeMask.strokeColor = [UIColor whiteColor].CGColor;
        self.darkEdgeMask.lineWidth = 0.525;
        self.darkEdgeRim.mask = self.darkEdgeMask;
        [self.layer addSublayer:self.darkEdgeRim];

        // 3. Specular Highlights: Inset inner rim with subtle glassy sheen
        self.specularRim = [CAGradientLayer layer];
        self.specularRim.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:_topSpecularOpacity * 0.45].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:_topSpecularOpacity * 0.20].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:_topSpecularOpacity * 0.20].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:_topSpecularOpacity * 0.45].CGColor
        ];
        self.specularRim.locations = @[@0.0, @0.055, @0.12, @0.88, @0.945, @1.0];
        self.specularRim.startPoint = CGPointMake(0.5, 0.0);
        self.specularRim.endPoint = CGPointMake(0.5, 1.0);

        self.rimMask = [CAShapeLayer layer];
        self.rimMask.fillColor = [UIColor clearColor].CGColor;
        self.rimMask.strokeColor = [UIColor whiteColor].CGColor;
        self.rimMask.lineWidth = _strokeWidth;
        self.specularRim.mask = self.rimMask;
        [self.layer addSublayer:self.specularRim];
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.fresnelGlare.frame = self.bounds;
    self.fresnelGlare.cornerRadius = self.cornerRadius;

    // Outer dark stroke
    self.darkEdgeRim.frame = self.bounds;
    UIBezierPath *outerPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.cornerRadius];
    self.darkEdgeMask.path = outerPath.CGPath;

    // Inner specular rim
    CGFloat specularInset = 0.85;
    CGRect innerRect = CGRectInset(self.bounds, specularInset, specularInset);
    if (CGRectGetWidth(innerRect) <= 0.0 || CGRectGetHeight(innerRect) <= 0.0) {
        innerRect = self.bounds;
    }
    CGFloat innerRadius = fmax(0.0, self.cornerRadius - specularInset);

    self.specularRim.frame = innerRect;
    self.rimMask.lineWidth = self.strokeWidth;
    UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, innerRect.size.width, innerRect.size.height) cornerRadius:innerRadius];
    self.rimMask.path = innerPath.CGPath;
}

@end
