#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface LGAdjustableBlurView : UIView

@property (nonatomic, assign) CGFloat cornerRadius;

@property (nonatomic, assign) CGFloat blurRadius;

@property (nonatomic, assign) CGFloat qualityScale;

@property (nonatomic, assign) BOOL capturesAppIcon;

- (instancetype)initWithFrame:(CGRect)frame blurRadius:(CGFloat)radius;

- (void)applyFilters;

@end
