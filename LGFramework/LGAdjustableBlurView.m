#import "LGAdjustableBlurView.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation LGAdjustableBlurView

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame blurRadius:(CGFloat)radius {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _blurRadius = radius;
    _qualityScale = 0.35;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    [self applyFilters];
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyFilters];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyFilters];
}

- (void)setBlurRadius:(CGFloat)blurRadius {
    if (fabs(_blurRadius - blurRadius) > 0.01) {
        _blurRadius = blurRadius;
        [self applyFilters];
    }
}

- (void)applyFilters {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    @try {
        [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@(!self.capturesAppIcon) forKey:@"windowServerAware"];
        if (self.capturesAppIcon) {
            [layer setValue:[NSString stringWithFormat:@"dylv.liquidglass.blur.%p", self] forKey:@"groupName"];
        }
        [layer setValue:@(self.qualityScale) forKey:@"scale"];

        NSArray *existing = layer.filters;
        if (existing.count == 1) {
            NSString *type = nil;
            @try { type = [existing[0] valueForKey:@"type"]; } @catch (...) {}
            if ([type isEqualToString:@"gaussianBlur"]) {
                NSNumber *rad = nil;
                @try { rad = [existing[0] valueForKey:@"inputRadius"]; } @catch (...) {}
                if (rad && fabs(rad.doubleValue - self.blurRadius) < 0.01) {
                    return;
                }
            }
        }

        Class filterCls = NSClassFromString(@"CAFilter");
        if (!filterCls) return;

        id blurFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"gaussianBlur");
        id satFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorSaturate");

        NSMutableArray *filters = [NSMutableArray array];
        if (blurFilter) {
            [blurFilter setValue:@(self.blurRadius) forKey:@"inputRadius"];
            [filters addObject:blurFilter];
        }
        if (satFilter) {
            [satFilter setValue:@1.80 forKey:@"inputAmount"];
            [filters addObject:satFilter];
        }
        layer.filters = filters;
    } @catch (NSException *e) {
    }
}

@end
