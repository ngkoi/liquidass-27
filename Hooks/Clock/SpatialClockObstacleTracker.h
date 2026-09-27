#import <UIKit/UIKit.h>
#import "SpatialLiquidClockView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SpatialClockObstacleTracker : NSObject

@property (nonatomic, weak, nullable) SpatialLiquidClockView *clockView;
@property (nonatomic, weak, nullable) UIView *containerView;
@property (nonatomic, weak, nullable) UIView *dateView;
@property (nonatomic, assign) BOOL isArtworkExpanded;
@property (nonatomic, assign) BOOL isSuspended;
@property (nonatomic, assign, readonly) CGFloat baseClockTop;
@property (nonatomic, assign, readonly) BOOL hasVisibleObstacles;
@property (nonatomic, copy, nullable) void (^onObstacleVisibilityChanged)(BOOL hasVisible);

+ (instancetype)sharedTracker;

- (void)registerObstacleView:(UIView *)view;
- (void)unregisterObstacleView:(UIView *)view;
- (void)notifyObstacleMoved;
- (void)wakeTracker;
- (void)checkObstacleVisibilityNow;

@end

NS_ASSUME_NONNULL_END
