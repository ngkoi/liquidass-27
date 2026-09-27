#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SpatialLiquidClockView : UIView

@property (nonatomic, copy) NSString *timeString;

@property (nonatomic, assign) CGFloat compressionProgress;

@property (nonatomic, assign) CGFloat userScale;

@property (nonatomic, assign) CGFloat userWeight;

@property (nonatomic, assign) CGFloat userSoftness;

@property (nonatomic, assign, readonly) CGFloat currentContentHeight;

@property (nonatomic, assign, readonly) CGFloat fullExpandedHeight;

@property (nonatomic, assign) BOOL isLiveOnScreen;

@property (nonatomic, assign) BOOL isInlineWithDate;


@property (nonatomic, assign) CGFloat blurRadius;

@property (nonatomic, assign) CGFloat bezelWidth;

@property (nonatomic, assign) CGFloat refractionAmount;

@property (nonatomic, assign) CGFloat refractionIndex;

- (instancetype)initWithFrame:(CGRect)frame;

- (void)updateClock;

- (void)applySettings:(id)settings;

- (void)notifySettled;

@end

NS_ASSUME_NONNULL_END
