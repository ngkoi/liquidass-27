#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SpatialClockObstacleTracker.h"
#import "SpatialClockSettings.h"
#import "SpatialLiquidClockView.h"
#import "../../Shared/LGGlassKit.h"
#import "../../Shared/LGSharedSupport.h"

extern BOOL LG_prefBool(NSString *key, BOOL fallback);
extern CGFloat LG_prefFloat(NSString *key, CGFloat fallback);
extern NSString *LG_prefString(NSString *key, NSString *fallback);

static void *kLGClockViewKey = &kLGClockViewKey;
static void *kLGClockSourceLabelKey = &kLGClockSourceLabelKey;
static void *kLGClockSourceAlphaKey = &kLGClockSourceAlphaKey;
static void *kLGClockVisibleSourceViewKey = &kLGClockVisibleSourceViewKey;
static void *kLGClockVisibleSourceAlphaKey = &kLGClockVisibleSourceAlphaKey;
static void *kLGClockVisibleSourceLayerOpacityKey = &kLGClockVisibleSourceLayerOpacityKey;
static void *kLGClockVisibleSourceHiddenKey = &kLGClockVisibleSourceHiddenKey;
static void *kLGClockApplyingDateKey = &kLGClockApplyingDateKey;
static void *kLGClockOriginalDateKey = &kLGClockOriginalDateKey;
static NSHashTable<UIView *> *sLGClockHosts;
static __weak UIView *sLGClockActiveHost;
static BOOL sLGClockPasscodeVisible;

@interface CSCoverSheetView : UIView
@end

@interface CSCombinedListViewController : UIViewController
@end

@interface NCNotificationListView : UIScrollView
@end

@interface NCNotificationListCell : UIView
@end

@interface NCNotificationListHeaderTitleView : UIView
@end

@interface CSProminentSubtitleDateView : UIView
@end

@interface MRUArtworkView : UIView
@end

void LGScheduleClockRecoveryRefreshForPresentationChange(void) {
    [[SpatialClockObstacleTracker sharedTracker] notifyObstacleMoved];
}

static BOOL LGClockEnabled(void) {
    return lgHostEnabled(@"Clock");
}

static BOOL LGClockLooksLikeTime(NSString *text) {
    if (text.length < 3 || text.length > 8) return NO;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    BOOL hasDigit = NO;
    BOOL hasSeparator = NO;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ([digits characterIsMember:character]) hasDigit = YES;
        else if (character == ':' || character == '.') hasSeparator = YES;
        else if (![[NSCharacterSet whitespaceCharacterSet] characterIsMember:character]) return NO;
    }
    return hasDigit && hasSeparator;
}

static void LGClockCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) LGClockCollectLabels(subview, labels);
}

static UILabel *LGClockSourceLabel(UIView *host) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    LGClockCollectLabels(host, labels);
    UILabel *best = nil;
    for (UILabel *label in labels) {
        NSString *text = label.text.length ? label.text : label.attributedText.string;
        if (!LGClockLooksLikeTime(text)) continue;
        if (!best || label.font.pointSize > best.font.pointSize) best = label;
    }
    return best;
}

static UIView *LGClockVisibleSourceViewForLabel(UILabel *label) {
    if (!label) return nil;
    for (UIView *view = label; view; view = view.superview) {
        if ([NSStringFromClass(view.class) isEqualToString:@"SBUILegibilityLabel"])
            return view;
    }
    return label;
}

static UIView *LGClockContainerForHost(UIView *host) {
    if ([NSStringFromClass(host.class) isEqualToString:@"CSProminentTimeView"]) {
        for (UIView *view = host.superview; view; view = view.superview) {
            if ([NSStringFromClass(view.class) isEqualToString:@"CSProminentDisplayView"])
                return view;
        }
    }
    UIView *container = host.superview;
    while (container.superview && ![container.superview isKindOfClass:UIWindow.class]) {
        NSString *name = NSStringFromClass(container.class);
        if ([name containsString:@"CoverSheet"] || [name containsString:@"DashBoard"]) break;
        container = container.superview;
    }
    return container ?: host.superview;
}

static CGRect LGClockFrameInContainer(UIView *host, UIView *container) {
    CGRect hostFrame = [container convertRect:host.bounds fromView:host];
    CGFloat top = CGRectGetMinY(hostFrame);
    CGFloat width = CGRectGetWidth(container.bounds);
    CGFloat height = MIN(360.0, MAX(80.0, CGRectGetHeight(container.bounds) - top));
    return CGRectMake(0.0, top, width, height);
}

static void LGClockRestoreSource(UIView *host) {
    UILabel *source = objc_getAssociatedObject(host, kLGClockSourceLabelKey);
    NSNumber *alpha = objc_getAssociatedObject(source, kLGClockSourceAlphaKey);
    if (source && alpha) source.alpha = alpha.doubleValue;
    objc_setAssociatedObject(source, kLGClockSourceAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(host, kLGClockSourceLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);

    UIView *visible = objc_getAssociatedObject(host, kLGClockVisibleSourceViewKey);
    NSNumber *visibleAlpha = objc_getAssociatedObject(host, kLGClockVisibleSourceAlphaKey);
    NSNumber *visibleOpacity = objc_getAssociatedObject(host, kLGClockVisibleSourceLayerOpacityKey);
    NSNumber *visibleHidden = objc_getAssociatedObject(host, kLGClockVisibleSourceHiddenKey);
    if (visible) {
        visible.alpha = visibleAlpha ? visibleAlpha.doubleValue : 1.0;
        visible.layer.opacity = visibleOpacity ? visibleOpacity.floatValue : 1.0f;
        visible.hidden = visibleHidden ? visibleHidden.boolValue : NO;
    }
    objc_setAssociatedObject(host, kLGClockVisibleSourceViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(host, kLGClockVisibleSourceAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(host, kLGClockVisibleSourceLayerOpacityKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(host, kLGClockVisibleSourceHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void LGClockApplyPasscodeVisibility(SpatialLiquidClockView *clock) {
    if (!clock) return;
    clock.hidden = sLGClockPasscodeVisible;
    clock.alpha = sLGClockPasscodeVisible ? 0.0 : 1.0;
}

void LGClockSetPasscodeVisible(BOOL visible) {
    sLGClockPasscodeVisible = visible;
    for (UIView *host in sLGClockHosts.allObjects) {
        LGClockApplyPasscodeVisibility(objc_getAssociatedObject(host, kLGClockViewKey));
    }
}

static void LGClockRemove(UIView *host) {
    SpatialLiquidClockView *clock = objc_getAssociatedObject(host, kLGClockViewKey);
    if ([SpatialClockObstacleTracker sharedTracker].clockView == clock) {
        SpatialClockObstacleTracker *tracker = [SpatialClockObstacleTracker sharedTracker];
        tracker.isSuspended = YES;
        tracker.clockView = nil;
        tracker.containerView = nil;
        tracker.dateView = nil;
    }
    [clock removeFromSuperview];
    objc_setAssociatedObject(host, kLGClockViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    LGClockRestoreSource(host);
    if (sLGClockActiveHost == host) sLGClockActiveHost = nil;
}

static NSInteger LGClockHostPriority(UIView *host) {
    return [NSStringFromClass(host.class) isEqualToString:@"CSProminentTimeView"] ? 2 : 1;
}

static void LGClockApplyPreferences(SpatialLiquidClockView *clock) {
    SpatialClockSettings *settings = [SpatialClockSettings sharedSettings];
    settings.blurRadius = LG_prefFloat(@"Clock.Blur", 2.0);
    settings.bezelWidth = LG_prefFloat(@"Clock.BezelWidth", 12.0);
    settings.refractionAmount = LG_prefFloat(@"Clock.RefractionScale", 1.6);
    settings.refractionIndex = LG_prefFloat(@"Clock.RefractiveIndex", 1.6);
    [clock applySettings:settings];
    clock.userScale = LG_prefFloat(@"Clock.VariableFont.SizeScale", 1.4);
    clock.userWeight = LG_prefFloat(@"Clock.VariableFont.Weight", 750.0);
    clock.userSoftness = LG_prefFloat(@"Clock.VariableFont.Softness", 56.0);
}

static void LGClockUpdateHost(UIView *host) {
    if (!host.window || !LGClockEnabled()) {
        LGClockRemove(host);
        return;
    }
    UILabel *source = LGClockSourceLabel(host);
    if (!source) return;
    if (sLGClockActiveHost != host) {
        if (sLGClockActiveHost.window &&
            LGClockHostPriority(sLGClockActiveHost) >= LGClockHostPriority(host)) return;
        LGClockRemove(sLGClockActiveHost);
        sLGClockActiveHost = host;
    }
    UIView *container = LGClockContainerForHost(host);
    if (!container) return;

    SpatialLiquidClockView *clock = objc_getAssociatedObject(host, kLGClockViewKey);
    if (!clock) {
        clock = [[SpatialLiquidClockView alloc] initWithFrame:LGClockFrameInContainer(host, container)];
        clock.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        clock.isLiveOnScreen = YES;
        [container addSubview:clock];
        objc_setAssociatedObject(host, kLGClockViewKey, clock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sLGClockHosts addObject:host];
    } else if (clock.superview != container) {
        [clock removeFromSuperview];
        [container addSubview:clock];
    }

    container.clipsToBounds = NO;
    container.layer.masksToBounds = NO;
    CGRect targetFrame = LGClockFrameInContainer(host, container);
    if (!CGRectIsEmpty(clock.frame)) targetFrame.origin.y = clock.frame.origin.y;
    clock.frame = targetFrame;
    NSString *time = source.text.length ? source.text : source.attributedText.string;
    if (LGClockLooksLikeTime(time)) clock.timeString = time;
    LGClockApplyPreferences(clock);
    [clock updateClock];

    UILabel *oldSource = objc_getAssociatedObject(host, kLGClockSourceLabelKey);
    if (oldSource != source) {
        LGClockRestoreSource(host);
        objc_setAssociatedObject(source, kLGClockSourceAlphaKey, @(source.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, kLGClockSourceLabelKey, source, OBJC_ASSOCIATION_ASSIGN);

        UIView *visible = LGClockVisibleSourceViewForLabel(source);
        if (visible && visible != source) {
            objc_setAssociatedObject(host, kLGClockVisibleSourceViewKey, visible,
                                     OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(host, kLGClockVisibleSourceAlphaKey, @(visible.alpha),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, kLGClockVisibleSourceLayerOpacityKey,
                                     @(visible.layer.opacity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, kLGClockVisibleSourceHiddenKey, @(visible.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    source.alpha = 0.0;
    UIView *visible = objc_getAssociatedObject(host, kLGClockVisibleSourceViewKey);
    if (visible && visible != source) {
        visible.hidden = YES;
        visible.alpha = 0.0;
        visible.layer.opacity = 0.0;
    }
    LGClockApplyPasscodeVisibility(clock);

    SpatialClockObstacleTracker *tracker = [SpatialClockObstacleTracker sharedTracker];
    tracker.clockView = clock;
    tracker.containerView = container;
    tracker.isSuspended = NO;
    [tracker notifyObstacleMoved];
}

static BOOL LGClockIsDateLabel(UILabel *label) {
    for (UIView *view = label; view; view = view.superview) {
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"SubtitleDateView"] ||
            [name isEqualToString:@"SBFLockScreenDateSubtitleDateView"]) return YES;
    }
    return NO;
}

static NSString *LGClockDateText(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ formatter = [NSDateFormatter new]; });
    formatter.locale = NSLocale.autoupdatingCurrentLocale;
    formatter.timeZone = NSTimeZone.localTimeZone;
    NSString *format = LG_prefString(@"Lockscreen.Clock.DateFormat.Format", @"");
    formatter.dateFormat = format.length ? format : [NSDateFormatter dateFormatFromTemplate:@"EEE d MMM"
                                                                          options:0
                                                                           locale:formatter.locale];
    return [formatter stringFromDate:NSDate.date];
}

static void LGClockUpdateDateLabel(UILabel *label) {
    if (!LGClockIsDateLabel(label)) return;
    SpatialClockObstacleTracker *tracker = [SpatialClockObstacleTracker sharedTracker];
    tracker.dateView = label.superview ?: label;
    if (!LG_prefBool(@"Lockscreen.Clock.DateFormat.Enabled", YES)) {
        NSString *original = objc_getAssociatedObject(label, kLGClockOriginalDateKey);
        if (original.length) label.text = original;
        return;
    }
    if (!objc_getAssociatedObject(label, kLGClockOriginalDateKey) && label.text.length) {
        objc_setAssociatedObject(label, kLGClockOriginalDateKey, label.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    objc_setAssociatedObject(label, kLGClockApplyingDateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    label.text = LGClockDateText();
    objc_setAssociatedObject(label, kLGClockApplyingDateKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void LGClockRegisterObstacle(UIView *view) {
    if (view.window) [[SpatialClockObstacleTracker sharedTracker] registerObstacleView:view];
    else [[SpatialClockObstacleTracker sharedTracker] unregisterObstacleView:view];
}

%group LGClock26Hooks

%hook CSProminentTimeView
- (void)didMoveToWindow { %orig; LGClockUpdateHost((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockUpdateHost((UIView *)self); }
%end

%hook SBFLockScreenDateView
- (void)didMoveToWindow { %orig; LGClockUpdateHost((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockUpdateHost((UIView *)self); }
%end

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (objc_getAssociatedObject(self, kLGClockApplyingDateKey)) return;
    LGClockUpdateDateLabel((UILabel *)self);
    if (LGClockLooksLikeTime(text)) {
        for (UIView *host in sLGClockHosts.allObjects) {
            if ([(UIView *)self isDescendantOfView:host]) LGClockUpdateHost(host);
        }
    }
}
%end

%hook PLPlatterView
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook NCNotificationShortLookView
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook NCNotificationLongLookView
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook NCNotificationListSectionRevealHintView
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook NCNotificationListCell
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook NCNotificationListHeaderTitleView
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook MRUArtworkView
- (void)didMoveToWindow { %orig; LGClockRegisterObstacle((UIView *)self); }
- (void)layoutSubviews { %orig; LGClockRegisterObstacle((UIView *)self); }
%end

%hook CSProminentSubtitleDateView
- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) {
        [SpatialClockObstacleTracker sharedTracker].dateView = (UIView *)self;
        [[SpatialClockObstacleTracker sharedTracker] notifyObstacleMoved];
    }
}
- (void)layoutSubviews {
    %orig;
    if (((UIView *)self).window) {
        [SpatialClockObstacleTracker sharedTracker].dateView = (UIView *)self;
    }
}
%end

%hook CSCoverSheetView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = %orig(point, event);
    if (result) {
        [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
    }
    return result;
}

- (void)layoutSubviews {
    %orig;
    if (![SpatialClockObstacleTracker sharedTracker].containerView) {
        [SpatialClockObstacleTracker sharedTracker].containerView = (UIView *)self;
    }
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
}
%end

%hook CSCombinedListViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
    [[SpatialClockObstacleTracker sharedTracker] checkObstacleVisibilityNow];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
    [[SpatialClockObstacleTracker sharedTracker] checkObstacleVisibilityNow];
}
%end

%hook NCNotificationListView
- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) {
        [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
        [[SpatialClockObstacleTracker sharedTracker] checkObstacleVisibilityNow];
    }
}

- (void)setContentOffset:(CGPoint)offset {
    %orig(offset);
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
}

- (void)_scrollViewWillBeginDragging {
    %orig;
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
    [[SpatialClockObstacleTracker sharedTracker] checkObstacleVisibilityNow];
}

- (void)_scrollViewDidEndDraggingWithDeceleration:(BOOL)decelerating {
    %orig;
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
    [[SpatialClockObstacleTracker sharedTracker] checkObstacleVisibilityNow];
}

- (void)_scrollViewDidEndDecelerating {
    %orig;
    [[SpatialClockObstacleTracker sharedTracker] wakeTracker];
    [[SpatialClockObstacleTracker sharedTracker] checkObstacleVisibilityNow];
}
%end

%hook PBUIPosterFloatingView
- (void)layoutSubviews {
    %orig;
    SpatialLiquidClockView *clock = [SpatialClockObstacleTracker sharedTracker].clockView;
    UIView *view = (UIView *)self;
    if (clock && view.superview == clock.superview) view.layer.zPosition = clock.layer.zPosition + 1.0;
}
%end

%end

%ctor {
    if (!LGIsSpringBoardProcess()) return;
    sLGClockHosts = [NSHashTable weakObjectsHashTable];
    %init(LGClock26Hooks);
    lgObservePreferenceReload(^{
        for (UIView *host in sLGClockHosts.allObjects) LGClockUpdateHost(host);
    });
}
