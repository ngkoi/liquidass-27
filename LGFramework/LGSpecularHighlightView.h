#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface LGSpecularHighlightView : UIView

@property (nonatomic, assign) CGFloat cornerRadius;

@property (nonatomic, assign) CGFloat strokeWidth;

@property (nonatomic, assign) CGFloat topSpecularOpacity;

@property (nonatomic, assign) CGFloat bottomSpecularOpacity;

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius;

@end
