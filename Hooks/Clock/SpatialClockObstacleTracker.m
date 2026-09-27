#import "SpatialClockObstacleTracker.h"
#import "SpatialLogging.h"
#import <QuartzCore/QuartzCore.h>

static CGRect SpatialGetPresentationFrameInContainer(UIView *view, UIView *container) {
    if (!view || !container || !view.window) {
        return CGRectNull;
    }
    if (view.hidden || view.alpha < 0.05) return CGRectNull;
    
    // validate all view ancestors
    UIView *anc = view.superview;
    while (anc && anc != container) {
        if (anc.hidden || anc.alpha < 0.05) return CGRectNull;
        if (anc.bounds.size.width <= 1.0 && anc.bounds.size.height <= 1.0) return CGRectNull;
        CALayer *ancPres = anc.layer.presentationLayer ?: anc.layer;
        if (ancPres.opacity < 0.05) return CGRectNull;
        anc = anc.superview;
    }
    
    CALayer *viewLayer = view.layer;
    CALayer *pres = viewLayer.presentationLayer ?: viewLayer;
    if (pres.opacity < 0.05) return CGRectNull;
    
    CALayer *containerLayer = container.layer.presentationLayer ?: container.layer;
    if (!containerLayer) return CGRectNull;
    
    CGRect rectInContainer = CGRectNull;
    @try {
        rectInContainer = [containerLayer convertRect:pres.bounds fromLayer:pres];
    } @catch (NSException *e) {
        rectInContainer = CGRectNull;
    }
    
    if (CGRectIsEmpty(rectInContainer) || CGRectIsNull(rectInContainer) || isnan(rectInContainer.origin.y)) {
        @try {
            rectInContainer = [container convertRect:view.bounds fromView:view];
        } @catch (NSException *e) {
            rectInContainer = CGRectNull;
        }
    }
    
    return rectInContainer;
}

@interface SpatialClockObstacleTracker ()
@property (nonatomic, strong) NSHashTable<UIView *> *obstacleViews;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger settledFrameCount;
@property (nonatomic, assign) CGFloat targetProgress;
@property (nonatomic, assign) CGFloat targetClockTop;
@property (nonatomic, assign) CGFloat lastLoggedProgress;
@end

@implementation SpatialClockObstacleTracker

+ (instancetype)sharedTracker {
    static SpatialClockObstacleTracker *tracker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tracker = [[SpatialClockObstacleTracker alloc] init];
    });
    return tracker;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _obstacleViews = [NSHashTable weakObjectsHashTable];
        _targetProgress = 1.0;
        _targetClockTop = 116.0;
        _lastLoggedProgress = -1.0;
        
        _isSuspended = YES;
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
        if (@available(iOS 15.0, *)) {
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0f, 120.0f, 120.0f);
        } else {
            _displayLink.preferredFramesPerSecond = 60;
        }
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _displayLink.paused = YES;
    }
    return self;
}

- (void)setIsSuspended:(BOOL)isSuspended {
    _isSuspended = isSuspended;
    if (isSuspended) {
        self.displayLink.paused = YES;
    } else {
        [self wakeTracker];
    }
}

- (void)dealloc {
    [_displayLink invalidate];
}

- (void)registerObstacleView:(UIView *)view {
    if (!view) return;
    [self.obstacleViews addObject:view];
    [self wakeTracker];
    [self checkObstacleVisibilityNow];
}

- (void)unregisterObstacleView:(UIView *)view {
    if (!view) return;
    [self.obstacleViews removeObject:view];
    [self wakeTracker];
    [self checkObstacleVisibilityNow];
}

- (void)checkObstacleVisibilityNow {
    SpatialLiquidClockView *clock = self.clockView;
    UIView *container = self.containerView ?: clock.superview;
    if (!container || !container.window) return;
    
    BOOL hasVisibleNotifs = NO;
    CGFloat screenHeight = container.bounds.size.height;
    if (screenHeight > 100.0) {
        for (UIView *view in self.obstacleViews) {
            if (!view.window || view.hidden || view.alpha < 0.05) continue;
            CGRect frame = SpatialGetPresentationFrameInContainer(view, container);
            if (CGRectIsNull(frame) || CGRectIsEmpty(frame)) continue;
            if (CGRectGetWidth(frame) < 140.0 || CGRectGetHeight(frame) < 20.0) continue;
            
            CGFloat maxRestingY = screenHeight * 0.68;
            if (CGRectGetMinY(frame) < maxRestingY && CGRectGetMaxY(frame) > 40.0) {
                hasVisibleNotifs = YES;
                break;
            }
        }
    }
    
    if (hasVisibleNotifs != _hasVisibleObstacles) {
        _hasVisibleObstacles = hasVisibleNotifs;
        SpatialLog(@"[CheckVis] detected visible platter state changed to %d", hasVisibleNotifs);
        if (self.onObstacleVisibilityChanged) {
            self.onObstacleVisibilityChanged(hasVisibleNotifs);
        }
    }
}

- (void)wakeTracker {
    if (self.isSuspended) return;
    self.settledFrameCount = 0;
    if (self.displayLink.isPaused) {
        self.displayLink.paused = NO;
    }
}

- (void)notifyObstacleMoved {
    // non blocking thing
    [self wakeTracker];
}

- (void)onDisplayLink:(CADisplayLink *)link {
    @autoreleasepool {
        [self recalculateCompression];
    }
}

- (void)recalculateCompression {
    if (self.isArtworkExpanded) {
        // artwork
        return;
    }
    
    SpatialLiquidClockView *clock = self.clockView;
    UIView *container = self.containerView ?: clock.superview;
    if (!clock || !container || !clock.window) return;
    
    UIView *dateView = self.dateView;
    CGFloat baseClockTop = 116.0;
    if (dateView && dateView.window) {
        CGRect dateFrame = SpatialGetPresentationFrameInContainer(dateView, container);
        if (!CGRectIsNull(dateFrame) && !CGRectIsEmpty(dateFrame) && CGRectGetWidth(dateFrame) > 50.0) {
            if (dateFrame.origin.y >= 40.0 && dateFrame.origin.y <= 110.0) {
                baseClockTop = CGRectGetMaxY(dateFrame) + 4.0;
            }
        }
    }
    _baseClockTop = baseClockTop;

    CGRect clockFrame = [clock convertRect:clock.bounds toView:container];
    CGFloat nearestTop = CGFLOAT_MAX;
    CGRect horizontalBand = CGRectInset(clockFrame, -20.0, 0.0);
    UIView *nearestView = nil;
    CGRect nearestFrame = CGRectZero;
    
    const CGFloat kClearanceMargin = 24.0; 
    const CGFloat kTopPadding = 6.0;       
    CGFloat clockMaxHeight = (clock.fullExpandedHeight > 100.0) ? clock.fullExpandedHeight : 330.0;
    CGFloat clockMaxReach = baseClockTop + clockMaxHeight + kClearanceMargin + kTopPadding;
    
    for (UIView *view in self.obstacleViews) {
        if (!view.window || view.hidden || view.alpha < 0.05) continue;
        
        CGRect frame = SpatialGetPresentationFrameInContainer(view, container);
        if (CGRectIsNull(frame) || CGRectIsEmpty(frame)) continue;
        

        if (CGRectGetWidth(frame) < 140.0 || CGRectGetHeight(frame) < 20.0) continue;
        
        if (CGRectGetMaxY(frame) <= -100.0) continue;
        
        if (CGRectGetMinY(frame) >= clockMaxReach - 8.0) continue;
        
        if (CGRectGetMinY(frame) >= nearestTop) continue;
        
        if (CGRectGetMaxX(frame) <= CGRectGetMinX(horizontalBand) ||
            CGRectGetMinX(frame) >= CGRectGetMaxX(horizontalBand)) continue;
        
        nearestTop = CGRectGetMinY(frame);
        nearestView = view;
        nearestFrame = frame;
    }

    
    CGFloat clockMinHeight = 65.0;     
    CGFloat targetTop = baseClockTop;
    CGFloat rawTargetProgress = 1.0;
    
    if (nearestTop == CGFLOAT_MAX || nearestTop >= 355.0f) {
        rawTargetProgress = 1.0;
        targetTop = baseClockTop;
    } else {
        CGFloat availableHeight = nearestTop - baseClockTop - kTopPadding - kClearanceMargin;
        CGFloat safeMaxHeight = 200.0f;
        if (availableHeight >= safeMaxHeight) {
            rawTargetProgress = 1.0;
            targetTop = baseClockTop;
        } else if (availableHeight > clockMinHeight) {
            rawTargetProgress = (availableHeight - clockMinHeight) / (safeMaxHeight - clockMinHeight);
            targetTop = baseClockTop;
        } else {
            rawTargetProgress = 0.0;
            CGFloat pushLimit = nearestTop - kClearanceMargin - kTopPadding - clockMinHeight;
            targetTop = MIN(baseClockTop, pushLimit);
        }
    }
    
    if (rawTargetProgress >= 0.94) {
        rawTargetProgress = 1.0;
    }
    self.targetProgress = MAX(0.0, MIN(1.0, rawTargetProgress));
    self.targetClockTop = targetTop;
    
    CGFloat currentP = clock.compressionProgress;
    CGFloat diffP = self.targetProgress - currentP;
    CGFloat newP;
    if (fabs(diffP) < 0.005 || (currentP >= 0.97 && self.targetProgress >= 0.999)) {
        newP = self.targetProgress;
    } else {
        CGFloat speed = (self.targetProgress < currentP) ? 0.22 : 0.16;
        newP = currentP + diffP * speed;
        if (newP >= 0.97 && self.targetProgress >= 0.999) {
            newP = 1.0;
        }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    clock.compressionProgress = newP;
    
    CGRect curFrame = clock.frame;
    CGFloat currentY = curFrame.origin.y;
    CGFloat diffY = self.targetClockTop - currentY;
    CGFloat newY;
    if (fabs(diffY) < 0.5) {
        newY = self.targetClockTop;
    } else {
        newY = currentY + diffY * 0.20;
    }
    if (fabs(curFrame.origin.y - newY) > 0.01) {
        clock.frame = CGRectMake(curFrame.origin.x, newY, curFrame.size.width, curFrame.size.height);
    }
    
    if (self.dateView && !self.isArtworkExpanded) {
        if (!CGAffineTransformIsIdentity(self.dateView.transform)) {
            self.dateView.transform = CGAffineTransformIdentity;
        }
    }
    [CATransaction commit];
    
    // pause dspl
    BOOL isProgressSettled = (fabs(clock.compressionProgress - self.targetProgress) < 0.005);
    BOOL isFrameSettled = (fabs(clock.frame.origin.y - self.targetClockTop) < 0.6);
    
    if (isProgressSettled && isFrameSettled) {
        self.settledFrameCount++;
        if (self.settledFrameCount == 1) {
            SpatialLog(@"[Tracker] Settled reached! TargetP=%.2f CurP=%.2f TargetTop=%.1f CurY=%.1f",
                       self.targetProgress, clock.compressionProgress, self.targetClockTop, clock.frame.origin.y);
            [clock notifySettled];
        }
        if (self.settledFrameCount > 35) {
            self.displayLink.paused = YES;
        }
    } else {
        self.settledFrameCount = 0;
    }
    
    if (fabs(self.targetProgress - self.lastLoggedProgress) > 0.08 || (self.displayLink.isPaused && self.lastLoggedProgress >= 0.0)) {
        self.lastLoggedProgress = self.targetProgress;
        SpatialLog(@"[Tracker] nearestTop=%.1f nearestView=%@ frame=%@ baseTop=%.1f targetP=%.2f curP=%.2f targetTop=%.1f obstacles=%lu",
                   (nearestTop == CGFLOAT_MAX ? -1.0 : nearestTop), (nearestView ? NSStringFromClass(nearestView.class) : @"none"), NSStringFromCGRect(nearestFrame), baseClockTop, self.targetProgress, clock.compressionProgress, self.targetClockTop, (unsigned long)self.obstacleViews.count);
    }
    
    [self checkObstacleVisibilityNow];
}


@end
