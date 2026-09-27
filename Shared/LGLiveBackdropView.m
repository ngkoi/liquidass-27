#import "LGLiveBackdropView.h"
#import "LGHostRegistry.h"
#import "LGCoverSheetState.h"
#import "LGFramework.h"
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <time.h>
#import <math.h>
#import <unistd.h>
#import <stdatomic.h>

static const void *kLGOutsetKey = &kLGOutsetKey;
static const void *kLGRadiusKey = &kLGRadiusKey;
static const void *kLGSpecularEnabledOverrideKey = &kLGSpecularEnabledOverrideKey;

static NSDictionary<NSString *, id> *sLGGlassPreferences;

static NSString *LGGlassPreferencesPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = jbroot(@"/var/mobile/Library/Preferences/dylv.liquidassprefs.plist");
    });
    return path;
}

id LGGlassPreferenceValue(NSString *key) {
    if (!key.length) return nil;
    @synchronized([LGLiveBackdropView class]) {
        if (!sLGGlassPreferences) {
            sLGGlassPreferences =
                [NSDictionary dictionaryWithContentsOfFile:LGGlassPreferencesPath()] ?: @{};
        }
        return sLGGlassPreferences[key];
    }
}

void LGInvalidateGlassPreferenceCache(void) {
    @synchronized([LGLiveBackdropView class]) {
        sLGGlassPreferences = nil;
    }
}

NSString *LGFilterTypeForHostPrefix(NSString *prefix) {
    if (!prefix.length) return nil;
    const LGHostDefinition *host =
        LGHostDefinitionForPreferencePrefix(prefix.UTF8String);
    return host ? [NSString stringWithUTF8String:host->filterType] : nil;
}

static void sblog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void sblog(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *format = [NSString stringWithUTF8String:fmt ?: ""];
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    LGLog(@"[LGSB] %@", message);
}

static const NSInteger kLGDynamicRadiusSteps = 32;

static BOOL LGNeedsGaussianIdentityFallback(void) {
    return access("/var/mobile/Library/Accessibility/liquidass-gaussian-identity-state.bin",
                  F_OK) == 0;
}

static CFStringRef const kLGParametersReloadedNotification =
    CFSTR("dylv.liquidglass/ParametersReloaded");
static NSHashTable<LGLiveBackdropView *> *sLGAllGlasses;
static BOOL sLGFilterRefreshSetup;
static BOOL LGSpecularEnabledForFilterType(NSString *type) {
    const LGHostDefinition *host = LGHostDefinitionForFilterType(type.UTF8String);
    if (host == &kLGHostRegistry[LGHostIdentifierCoverSheet]) return NO;
    if (host && host->specularOpacity <= 0.001f) return NO;
    NSString *prefix = host ? [NSString stringWithUTF8String:host->preferencePrefix] : nil;
    if (!prefix.length) return YES;
    id value = LGGlassPreferenceValue([prefix stringByAppendingString:@".SpecularEnabled"]);
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

static NSHashTable<LGLiveBackdropView *> *sLGMotionGlasses;
static CMMotionManager *sLGMotionManager;
static NSOperationQueue *sLGMotionQueue;
static BOOL sLGMotionSetup;
static BOOL sLGMotionRunning;
static CGFloat sLGSpecularAngle = -M_PI_2;
static CGFloat sLGTargetSpecularAngle = -M_PI_2;
static CGFloat sLGLastTargetSpecularAngle = -M_PI_2;
static CGFloat sLGLastAppliedSpecularAngle = -100.0;
static CADisplayLink *sLGMotionDisplayLink;
static BOOL sLGMotionEnabled;
static CGFloat sLGMotionSensitivity = 2.0;
static CGFloat sLGMotionLoggedSensitivity = -1.0;
static CFStringRef const kLGMotionPrefsReloadNotification = CFSTR("dylv.liquidassprefs/Reload");

static void LGApplyMotionHighlightAngle(void);
static void LGRefreshMotionHighlights(void);
static void LGEnsureFilterRefreshObserver(void);

@interface LGMotionDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)displayLink;
@end

static BOOL LGIsSpringBoardBundle(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

static void LGReloadMotionHighlightPreferences(void) {
    id enabled = LGGlassPreferenceValue(@"Specular.Motion.Enabled");
    id sensitivity = LGGlassPreferenceValue(@"Specular.Motion.Sensitivity");
    BOOL previousEnabled = sLGMotionEnabled;
    CGFloat previousSensitivity = sLGMotionSensitivity;
    sLGMotionEnabled = [enabled respondsToSelector:@selector(boolValue)] ? [enabled boolValue] : NO;
    CGFloat value = [sensitivity respondsToSelector:@selector(doubleValue)] ? [sensitivity doubleValue] : 2.0;
    sLGMotionSensitivity = MAX(0.0, MIN(8.0, value));
    if (sLGMotionLoggedSensitivity < 0.0 || previousEnabled != sLGMotionEnabled ||
        fabs(previousSensitivity - sLGMotionSensitivity) > 0.01) {
        sLGMotionLoggedSensitivity = sLGMotionSensitivity;
        LGLog(@"motion highlights prefs enabled=%d sensitivity=%.2f", sLGMotionEnabled, sLGMotionSensitivity);
    }
}

static void LGMotionPreferencesDidChange(CFNotificationCenterRef center, void *observer,
                                         CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        LGInvalidateGlassPreferenceCache();
        LGReloadMotionHighlightPreferences();
        LGRefreshMotionHighlights();
        for (LGLiveBackdropView *glass in sLGMotionGlasses.allObjects) {
            [glass invalidateSpecularCache];
        }
    });
}

static BOOL LGUsesDynamicRadiusType(NSString *filterType) {

    return filterType.length &&
           LGHostIdentifierForFilterType(filterType.UTF8String) != LGHostIdentifierClock;
}

static CGFloat LGNativeBlurRadiusForFilterType(NSString *filterType) {
    const LGHostDefinition *host = LGHostDefinitionForFilterType(filterType.UTF8String);
    if (!host) return 0.0;
    if (LGHostIdentifierForDefinition(host) == LGHostIdentifierControlCenter) {
        return 0.0;
    }
    NSString *prefix = [NSString stringWithUTF8String:host->preferencePrefix];
    id value = LGGlassPreferenceValue([prefix stringByAppendingString:@".Blur"]);
    return [value respondsToSelector:@selector(doubleValue)]
        ? MAX(0.0, [value doubleValue]) : host->blur;
}

static const CGFloat kLGScaleMax    = 0.75;
static const CGFloat kLGScaleMin    = 0.25;
static const CGFloat kLGCustomScaleMin = 0.10;
static const CGFloat kLGCustomScaleMax = 1.50;

static const CGFloat kLGDefaultScaleBudget = 8000.0;
static CGFloat LGScaleBudget(void) {
    id value = LGGlassPreferenceValue(@"Global.ScaleBudget");
    CGFloat budget = [value respondsToSelector:@selector(doubleValue)]
        ? (CGFloat)[value doubleValue] : kLGDefaultScaleBudget;
    if (!isfinite(budget)) budget = kLGDefaultScaleBudget;
    return fmin(32000.0, fmax(1000.0, budget));
}

static NSNumber *LGCustomScaleForFilterType(NSString *filterType) {
    const LGHostDefinition *host = LGHostDefinitionForFilterType(filterType.UTF8String);
    if (!host) return nil;
    NSString *prefix = [NSString stringWithUTF8String:host->preferencePrefix];
    id enabled = LGGlassPreferenceValue([prefix stringByAppendingString:@".CustomScaleEnabled"]);
    enum LGHostIdentifier identifier = LGHostIdentifierForDefinition(host);
    BOOL enabledByDefault = identifier == LGHostIdentifierClock ||
        identifier == LGHostIdentifierCoverSheet ||
        identifier == LGHostIdentifierTabBar ||
        identifier == LGHostIdentifierTabBarSelection ||
        identifier == LGHostIdentifierPrefsSlider ||
        identifier == LGHostIdentifierPrefsSwitch ||
        identifier == LGHostIdentifierPrefsButton ||
        identifier == LGHostIdentifierPrefsSegment;
    BOOL customScaleEnabled = [enabled respondsToSelector:@selector(boolValue)]
        ? [enabled boolValue] : enabledByDefault;
    if (!customScaleEnabled) return nil;
    id value = LGGlassPreferenceValue([prefix stringByAppendingString:@".CustomScale"]);
    BOOL prefsControl = identifier == LGHostIdentifierPrefsSlider ||
        identifier == LGHostIdentifierPrefsSwitch ||
        identifier == LGHostIdentifierPrefsButton ||
        identifier == LGHostIdentifierPrefsSegment;
    CGFloat fallback = prefsControl ? 1.50 : 1.00;
    CGFloat scale = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    if (!isfinite(scale)) scale = fallback;
    return @(fmin(kLGCustomScaleMax, fmax(kLGCustomScaleMin, scale)));
}

static CGFloat LGScaleForSize(CGSize s) {
    CGFloat area = s.width * s.height;
    if (area <= 1.0) return kLGScaleMax;
    CGFloat scale = sqrt(LGScaleBudget() / area);
    return fmin(kLGScaleMax, fmax(kLGScaleMin, scale));
}

@interface LGLiveBackdropView ()
- (void)updateSpecular;
- (void)applySpecularAngle:(CGFloat)angle;
- (void)reapplyFilterForParameterReload;
@end

static void LGParametersReloaded(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object,
                                 CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{

        LGInvalidateGlassPreferenceCache();
        NSArray<LGLiveBackdropView *> *glasses = sLGAllGlasses.allObjects;
        LGLog(@"render parameters ready; refreshing %lu live filters",
              (unsigned long)glasses.count);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (LGLiveBackdropView *glass in glasses) {
            [glass reapplyFilterForParameterReload];
        }
        [CATransaction commit];
    });
}

static void LGEnsureFilterRefreshObserver(void) {
    if (!sLGAllGlasses) sLGAllGlasses = [NSHashTable weakObjectsHashTable];
    if (sLGFilterRefreshSetup) return;
    sLGFilterRefreshSetup = YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    LGParametersReloaded,
                                    kLGParametersReloadedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

static void LGApplyMotionHighlightAngle(void) {
    if (sLGMotionGlasses.count == 0) return;
    if (sLGMotionDisplayLink && sLGMotionDisplayLink.paused &&
        fabs(sLGSpecularAngle - sLGLastAppliedSpecularAngle) < 0.001) return;
    sLGLastAppliedSpecularAngle = sLGSpecularAngle;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (LGLiveBackdropView *glass in sLGMotionGlasses.allObjects) {
        UIWindow *window = glass.window;
        if (!window || glass.hidden || glass.alpha <= 0.01 ||
            window.hidden || window.alpha <= 0.01) continue;
        CGRect bounds = glass.bounds;
        if (CGRectIsEmpty(bounds) ||
            !CGRectIntersectsRect(window.bounds, [glass convertRect:bounds toView:nil])) continue;
        [glass applySpecularAngle:sLGSpecularAngle];
    }
    [CATransaction commit];
}

@implementation LGMotionDisplayLinkTarget
- (void)tick:(CADisplayLink *)displayLink {
    CGFloat dt = displayLink.targetTimestamp > displayLink.timestamp
        ? displayLink.targetTimestamp - displayLink.timestamp : 1.0 / 60.0;
    CGFloat delta = atan2(sin(sLGTargetSpecularAngle - sLGSpecularAngle),
                          cos(sLGTargetSpecularAngle - sLGSpecularAngle));
    if (fabs(delta) < 0.001) {
        sLGSpecularAngle = sLGTargetSpecularAngle;
        LGApplyMotionHighlightAngle();
        displayLink.paused = YES;
        return;
    }
    CGFloat response = 1.0 - exp(-14.0 * dt);
    sLGSpecularAngle += delta * response;
    LGApplyMotionHighlightAngle();
}
@end

static void LGRefreshMotionHighlights(void) {
    if (!sLGMotionSetup || !LGIsSpringBoardBundle()) return;
    if (!sLGMotionEnabled) {
        [sLGMotionManager stopDeviceMotionUpdates];
        [sLGMotionDisplayLink invalidate];
        sLGMotionDisplayLink = nil;
        sLGMotionRunning = NO;
        sLGSpecularAngle = -M_PI_2;
        sLGTargetSpecularAngle = sLGSpecularAngle;
        sLGLastAppliedSpecularAngle = -100.0;
        LGApplyMotionHighlightAngle();
        return;
    }
    if (sLGMotionRunning) return;

    if (!sLGMotionQueue) {
        sLGMotionQueue = [[NSOperationQueue alloc] init];
        sLGMotionQueue.name = @"com.ngkhoi.liquidass.motion";
        sLGMotionQueue.maxConcurrentOperationCount = 1;
        sLGMotionQueue.qualityOfService = NSQualityOfServiceUtility;
    }

    CMAttitudeReferenceFrame frame = CMAttitudeReferenceFrameXArbitraryZVertical;

    sLGMotionManager.deviceMotionUpdateInterval = 1.0 / 30.0;
    static LGMotionDisplayLinkTarget *displayLinkTarget;
    if (!displayLinkTarget) displayLinkTarget = [LGMotionDisplayLinkTarget new];
    if (!sLGMotionDisplayLink) {
        sLGMotionDisplayLink = [CADisplayLink displayLinkWithTarget:displayLinkTarget
                                                           selector:@selector(tick:)];
        [sLGMotionDisplayLink addToRunLoop:NSRunLoop.mainRunLoop
                                   forMode:NSRunLoopCommonModes];
    }
    sLGMotionRunning = YES;
    [sLGMotionManager startDeviceMotionUpdatesUsingReferenceFrame:frame
                                                            toQueue:sLGMotionQueue
                                                        withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (!motion || error || !sLGMotionEnabled) return;
        CMAttitude *attitude = motion.attitude;

        CGFloat baseMotion = attitude.roll * 1.2 + attitude.pitch * 1.2 + attitude.yaw;
        CGFloat target = baseMotion * (sLGMotionSensitivity * 1.2);
        CGFloat delta = atan2(sin(target - sLGLastTargetSpecularAngle),
                              cos(target - sLGLastTargetSpecularAngle));
        if (fabs(delta) <= 0.001) return;
        sLGLastTargetSpecularAngle = target;
        sLGTargetSpecularAngle = target;
        if (sLGMotionDisplayLink && sLGMotionDisplayLink.paused) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sLGMotionDisplayLink.paused = NO;
            });
        }
    }];
    LGLog(@"motion highlights started reference=tilt+yaw rate=30Hz high-sensitivity");
}

static void LGEnsureMotionHighlights(void) {
    if (!LGIsSpringBoardBundle()) return;
    if (!sLGMotionGlasses) sLGMotionGlasses = [NSHashTable weakObjectsHashTable];
    if (!sLGMotionManager) sLGMotionManager = [CMMotionManager new];
    if (!sLGMotionSetup) {
        sLGMotionSetup = YES;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        LGMotionPreferencesDidChange,
                                        kLGMotionPrefsReloadNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    LGReloadMotionHighlightPreferences();
    LGRefreshMotionHighlights();
}

static const CGFloat kLGGlassEdgeWidth = 0.525;
static const CGFloat kLGGlassSpecularWidth = 0.50;
static const CGFloat kLGGlassSpecularInset = 0.85;

@implementation LGLiveBackdropView {
    NSString        *_lgGroupName;
    CAGradientLayer *_fresnelGlareLayer;
    CAGradientLayer *_darkEdgeLayer;
    CAShapeLayer    *_darkEdgeMask;
    CAGradientLayer *_specularLayer;
    CAShapeLayer    *_specularMask;
    CAShapeLayer    *_edge;
    UIView          *_nativeBlurView;
    CGFloat          _nativeBlurRadius;
    BOOL             _backdropConfigured;
    BOOL             _filterAttached;
    uint32_t         _lgId;
    CGFloat          _appliedScale;
    CGFloat          _appliedBackdropZoom;
    BOOL             _parameterRefreshVariant;
    NSInteger        _lastRadiusStep;
    CGFloat          _appliedSpecularOpacity;
    CGFloat          _appliedFresnelStrength;
}

- (NSString *)lgEffectiveFilterType {
    if (!_lgFilterType.length)
        return [NSString stringWithUTF8String:kLGHostRegistry[LGHostIdentifierDefault].filterType];
    NSString *base = _lgFilterType;

    if (LGUsesDynamicRadiusType(base) && !CGRectIsEmpty(self.bounds)) {
        CGFloat shortest = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
        BOOL keyboard = LGHostIdentifierForFilterType(base.UTF8String) ==
            LGHostIdentifierKeyboard;
        CGFloat radius = keyboard ? _lgShapeCornerRadius : self.layer.cornerRadius;
        CGFloat ratio = shortest > 0.0 ? radius / shortest : 0.0;
        CGFloat exact = MAX(0.0, MIN(0.5, ratio)) * kLGDynamicRadiusSteps;
        NSInteger step = (NSInteger)llround(exact);
        if (_lastRadiusStep >= 0 && fabs(exact - (CGFloat)_lastRadiusStep) < 0.75)
            step = _lastRadiusStep;
        _lastRadiusStep = step;
        base = [base stringByAppendingFormat:@".r%ld", (long)step];
    }
    NSString *type = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [base stringByAppendingString:@".dark"] : base;
    if (_parameterRefreshVariant) type = [type stringByAppendingString:@".refresh"];
    return type;
}

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame groupName:nil filterType:nil];
}

- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)groupName {
    return [self initWithFrame:frame groupName:groupName filterType:nil];
}

- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)groupName filterType:(NSString *)filterType {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _lastRadiusStep = -1;
    _appliedSpecularOpacity = -1.0;
    _lgShapeRect = CGRectNull;
    _lgFilterType = [filterType copy];
    static atomic_uint idCounter = 0;
    _lgId = atomic_fetch_add(&idCounter, 1) + 1;
    if (groupName.length) {
        _lgGroupName = [groupName copy];
    } else {
        static uint32_t salt = 0;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ salt = arc4random(); });
        _lgGroupName = [NSString stringWithFormat:@"dylv.liquidglass.p%d.%08x.g%u",
                                                  getpid(), salt, _lgId];
    }
    self.userInteractionEnabled = NO;
    self.backgroundColor        = [UIColor clearColor];
    self.opaque                 = NO;

    self.autoresizingMask       = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    LGEnsureFilterRefreshObserver();
    [sLGAllGlasses addObject:self];
    LGEnsureMotionHighlights();
    [sLGMotionGlasses addObject:self];
    [self applyFilters];
    return self;
}

- (void)dealloc {
    [sLGAllGlasses removeObject:self];
    [sLGMotionGlasses removeObject:self];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyFilters];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        _filterAttached = NO;
        [self applyFilters];
        [self updateSpecular];
        }
}

- (NSNumber *)lgSpecularEnabledOverride {
    return objc_getAssociatedObject(self, kLGSpecularEnabledOverrideKey);
}

- (void)setLgSpecularEnabledOverride:(NSNumber *)override {
    NSNumber *previous = self.lgSpecularEnabledOverride;
    if ((previous == override) || [previous isEqualToNumber:override]) return;
    objc_setAssociatedObject(self, kLGSpecularEnabledOverrideKey, [override copy],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self updateSpecular];
}

- (void)setLgSpecularOpacityOverride:(NSNumber *)override {
    NSNumber *previous = self.lgSpecularOpacityOverride;
    if ((previous == override) || [previous isEqualToNumber:override]) return;
    objc_setAssociatedObject(self, @selector(lgSpecularOpacityOverride), override,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    _appliedSpecularOpacity = -1.0;
    [self updateSpecular];
}

- (NSNumber *)lgSpecularOpacityOverride {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setLgNativeBlurRadiusOverride:(NSNumber *)override {
    NSNumber *previous = self.lgNativeBlurRadiusOverride;
    if ((previous == override) || [previous isEqualToNumber:override]) return;
    objc_setAssociatedObject(self, @selector(lgNativeBlurRadiusOverride), override,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self applyFilters];
}

- (NSNumber *)lgNativeBlurRadiusOverride {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setLgQualityScaleOverride:(NSNumber *)override {
    NSNumber *previous = self.lgQualityScaleOverride;
    if ((previous == override) || [previous isEqualToNumber:override]) return;
    objc_setAssociatedObject(self, @selector(lgQualityScaleOverride), override,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    _appliedScale = -1.0;
    [self applyFilters];
}

- (NSNumber *)lgQualityScaleOverride {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyFilters];
    [self updateSpecular];
    if (_nativeBlurView) {
        _nativeBlurView.frame = self.bounds;
        _nativeBlurView.layer.cornerRadius = self.layer.cornerRadius;
        _nativeBlurView.layer.cornerCurve = self.layer.cornerCurve;
    }
}

- (void)updateNativeBlurOverlayWithRadius:(CGFloat)radius {
    if (radius <= 0.01) {
        if (_nativeBlurView) {
            [_nativeBlurView removeFromSuperview];
            _nativeBlurView = nil;
            _nativeBlurRadius = 0.0;
        }
        return;
    }

    if (!_nativeBlurView) {
        _nativeBlurView = [[LGAdjustableBlurView alloc] initWithFrame:self.bounds blurRadius:radius];
        _nativeBlurView.userInteractionEnabled = NO;
        [self insertSubview:_nativeBlurView atIndex:0];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _nativeBlurView.frame = self.bounds;
    _nativeBlurView.layer.cornerRadius = self.layer.cornerRadius;
    _nativeBlurView.layer.cornerCurve = self.layer.cornerCurve;
    _nativeBlurView.clipsToBounds = YES;
    if ([_nativeBlurView respondsToSelector:@selector(setCornerRadius:)]) {
        [(LGAdjustableBlurView *)_nativeBlurView setCornerRadius:self.layer.cornerRadius];
    }
    if (fabs(_nativeBlurRadius - radius) > 0.001) {
        if ([_nativeBlurView respondsToSelector:@selector(setBlurRadius:)]) {
            [(LGAdjustableBlurView *)_nativeBlurView setBlurRadius:radius];
        }
        _nativeBlurRadius = radius;
    }
    [CATransaction commit];
}

- (void)setLgShapeRect:(CGRect)rect {
    if (CGRectEqualToRect(_lgShapeRect, rect)) return;
    _lgShapeRect = rect;
    if (LGHostIdentifierForFilterType(_lgFilterType.UTF8String) ==
        LGHostIdentifierKeyboard) {
        _filterAttached = NO;
        [self applyFilters];
    }
    [self updateSpecular];
}

- (void)setLgShapeCornerRadius:(CGFloat)radius {
    if (fabs(_lgShapeCornerRadius - radius) < 0.01) return;
    _lgShapeCornerRadius = radius;
    if (LGHostIdentifierForFilterType(_lgFilterType.UTF8String) ==
        LGHostIdentifierKeyboard) {
        _filterAttached = NO;
        [self applyFilters];
    }
    [self updateSpecular];
}

- (void)invalidateSpecularCache {
    _appliedSpecularOpacity = -1.0;
    _appliedFresnelStrength = -1.0;
    [self updateSpecular];
}

- (void)updateSpecular {
    if (CGRectIsEmpty(self.bounds)) return;

    BOOL hasShape = !CGRectIsNull(_lgShapeRect) && !CGRectIsEmpty(_lgShapeRect);
    CGRect shapeRect = hasShape ? _lgShapeRect : self.bounds;
    CGFloat shapeRadius = hasShape ? _lgShapeCornerRadius
                                   : self.layer.cornerRadius;
    if (shapeRadius <= 0.0 && self.superview) {
        shapeRadius = self.superview.layer.cornerRadius;
    }
    CGFloat shortest = fmin(CGRectGetWidth(shapeRect), CGRectGetHeight(shapeRect));
    CGFloat maxRadius = shortest * 0.5;
    if (shapeRadius > maxRadius) shapeRadius = maxRadius;

    BOOL isCircleOrPill = (shapeRadius >= maxRadius - 1.5 && maxRadius > 0.0);
    NSString *curve = isCircleOrPill ? kCACornerCurveCircular : (self.layer.cornerCurve ?: kCACornerCurveContinuous);
    self.layer.cornerCurve = curve;

    NSNumber *override = self.lgSpecularEnabledOverride;
    BOOL enabled = override ? override.boolValue
                            : LGSpecularEnabledForFilterType(_lgFilterType);
    const LGHostDefinition *host = LGHostDefinitionForFilterType(_lgFilterType.UTF8String);
    if (host == &kLGHostRegistry[LGHostIdentifierClock]) return;
    if (!enabled && !_specularLayer && !_darkEdgeLayer && !_fresnelGlareLayer) return;

    if (_edge) {
        [_edge removeFromSuperlayer];
        _edge = nil;
    }

    CGFloat maxAlpha = self.lgSpecularOpacityOverride
        ? self.lgSpecularOpacityOverride.doubleValue : 0.85;
    if (!self.lgSpecularOpacityOverride && host) {
        NSString *prefix = [NSString stringWithUTF8String:host->preferencePrefix];
        id value = prefix.length
            ? LGGlassPreferenceValue([prefix stringByAppendingString:@".SpecularOpacity"])
            : nil;
        if ([value respondsToSelector:@selector(doubleValue)])
            maxAlpha = [value doubleValue];
        else if (host->specularOpacity > 0.001f)
            maxAlpha = host->specularOpacity;
    }
    maxAlpha = fmax(0.0, fmin(1.0, maxAlpha));

    CGFloat fresnelStrength = 0.5;
    id fresnelVal = LGGlassPreferenceValue(@"Renderer.FresnelGlareStrength");
    if ([fresnelVal respondsToSelector:@selector(doubleValue)]) {
        fresnelStrength = [fresnelVal doubleValue];
    }
    fresnelStrength = fmax(0.0, fmin(1.0, fresnelStrength));
    CGFloat glarePeakAlpha = (fresnelStrength * 0.312) * maxAlpha;

    id clear = (id)UIColor.clearColor.CGColor;

    if (!_fresnelGlareLayer) {
        _fresnelGlareLayer = [CAGradientLayer layer];
        _fresnelGlareLayer.locations = @[
            @0.0, @0.035, @0.09, @0.18, @0.28,
            @0.72, @0.82, @0.91, @0.965, @1.0
        ];
        if (_nativeBlurView) {
            [self.layer insertSublayer:_fresnelGlareLayer above:_nativeBlurView.layer];
        } else {
            [self.layer insertSublayer:_fresnelGlareLayer atIndex:0];
        }
    }

    if (!_darkEdgeLayer) {
        _darkEdgeLayer = [CAGradientLayer layer];
        _darkEdgeLayer.locations = @[@0.0, @0.15, @0.30, @0.70, @0.85, @1.0];
        _darkEdgeMask = [CAShapeLayer layer];
        _darkEdgeMask.backgroundColor = UIColor.clearColor.CGColor;
        _darkEdgeMask.borderColor = UIColor.whiteColor.CGColor;
        _darkEdgeMask.borderWidth = kLGGlassEdgeWidth;
        _darkEdgeLayer.mask = _darkEdgeMask;
        [self.layer addSublayer:_darkEdgeLayer];
    }

    if (!_specularLayer) {
        _specularLayer = [CAGradientLayer layer];
        _specularLayer.locations = @[@0.0, @0.055, @0.12, @0.88, @0.945, @1.0];
        _specularMask = [CAShapeLayer layer];
        _specularMask.backgroundColor = UIColor.clearColor.CGColor;
        _specularMask.borderColor = UIColor.whiteColor.CGColor;
        _specularMask.borderWidth = kLGGlassSpecularWidth;
        _specularLayer.mask = _specularMask;
        [self.layer addSublayer:_specularLayer];
    }

    if (_darkEdgeLayer && _specularLayer) {
        [self.layer insertSublayer:_darkEdgeLayer below:_specularLayer];
    }

    if (fabs(_appliedSpecularOpacity - maxAlpha) > 0.001 ||
        fabs(_appliedFresnelStrength - fresnelStrength) > 0.001) {
        _fresnelGlareLayer.locations = @[
            @0.0, @0.035, @0.09, @0.18, @0.28,
            @0.72, @0.82, @0.91, @0.965, @1.0
        ];
        _fresnelGlareLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha * 0.55].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha * 0.22].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha * 0.06].CGColor,
            clear,
            clear,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha * 0.06].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha * 0.22].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha * 0.55].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:glarePeakAlpha].CGColor
        ];

        _darkEdgeLayer.colors = @[
            (id)[UIColor colorWithWhite:0.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.48].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.48].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.28].CGColor
        ];

        _specularLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.45].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.20].CGColor,
            clear,
            clear,
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.20].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.45].CGColor
        ];
        _appliedSpecularOpacity = maxAlpha;
        _appliedFresnelStrength = fresnelStrength;
    }

    CGRect specularRect = CGRectInset(shapeRect, kLGGlassSpecularInset, kLGGlassSpecularInset);
    if (CGRectGetWidth(specularRect) <= 0.0 || CGRectGetHeight(specularRect) <= 0.0) {
        specularRect = shapeRect;
    }
    CGFloat specularRadius = fmax(0.0, shapeRadius - kLGGlassSpecularInset);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fresnelGlareLayer.hidden = (!enabled || fresnelStrength <= 0.001);
    _fresnelGlareLayer.frame = shapeRect;
    _fresnelGlareLayer.cornerRadius = shapeRadius;
    _fresnelGlareLayer.cornerCurve = curve;
    _fresnelGlareLayer.masksToBounds = YES;

    _darkEdgeLayer.hidden = !enabled;
    _darkEdgeLayer.frame = shapeRect;
    _darkEdgeMask.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(shapeRect), CGRectGetHeight(shapeRect));
    _darkEdgeMask.cornerRadius = shapeRadius;
    _darkEdgeMask.cornerCurve = curve;
    _darkEdgeMask.borderWidth = kLGGlassEdgeWidth;

    _specularLayer.hidden = !enabled;
    _specularLayer.frame = specularRect;
    _specularMask.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(specularRect), CGRectGetHeight(specularRect));
    _specularMask.cornerRadius = specularRadius;
    _specularMask.cornerCurve = curve;
    _specularMask.borderWidth = kLGGlassSpecularWidth;
    [CATransaction commit];
    [self applySpecularAngle:sLGSpecularAngle];
}

- (void)applySpecularAngle:(CGFloat)angle {
    CGFloat dx = cos(angle) * 0.25;
    if (_specularLayer) {
        _specularLayer.startPoint = CGPointMake(0.5 + dx, 0.0);
        _specularLayer.endPoint   = CGPointMake(0.5 - dx, 1.0);
    }
    if (_darkEdgeLayer) {
        _darkEdgeLayer.startPoint = CGPointMake(0.5 + dx, 0.0);
        _darkEdgeLayer.endPoint   = CGPointMake(0.5 - dx, 1.0);
    }
    if (_fresnelGlareLayer) {
        _fresnelGlareLayer.startPoint = CGPointMake(0.5 + dx * 0.4, 0.0);
        _fresnelGlareLayer.endPoint   = CGPointMake(0.5 - dx * 0.4, 1.0);
    }
}

- (void)applyFilters {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    @try {

        if (!_backdropConfigured) {
            // these private flags keep capture in render server space
            [layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
            [layer setValue:@NO forKey:@"windowServerAware"];
            [layer setValue:_lgGroupName forKey:@"groupName"];
            [layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];

            [layer setValue:@YES forKey:@"ignoresScreenClip"];
            _backdropConfigured = YES;
        }

        CGFloat wantScale;
        NSNumber *customScale = LGCustomScaleForFilterType(_lgFilterType);
        if (self.lgQualityScaleOverride) {
            wantScale = self.lgQualityScaleOverride.doubleValue;
        } else if (customScale) {
            wantScale = customScale.doubleValue;
        } else {
            wantScale = LGScaleForSize(self.bounds.size);
        }
        CGFloat wantZoom = _lgBackdropZoom > 0.0 ? _lgBackdropZoom : 1.0;
        BOOL zoomRelevant = fabs(wantZoom - 1.0) > 0.001 || _appliedBackdropZoom > 0.0;
        if (zoomRelevant && fabs(wantZoom - _appliedBackdropZoom) > 0.001) {
            _appliedBackdropZoom = wantZoom;
            @try { [layer setValue:@(wantZoom) forKey:@"zoom"]; }
            @catch (__unused NSException *exception) {}
            LGLog(@"glass#%u zoom type=%@ want=%.3f readback=%@", _lgId,
                  _lgFilterType ?: @"default", wantZoom,
                  [layer valueForKey:@"zoom"] ?: @"<none>");
        }

        if (fabs(wantScale - _appliedScale) > 0.02) {
            [layer setValue:@(wantScale) forKey:@"scale"];
            _appliedScale = wantScale;
        }

        NSString *wantType = [self lgEffectiveFilterType];
        Class filterCls = NSClassFromString(@"CAFilter");
        CGFloat blurRadius = self.lgNativeBlurRadiusOverride
            ? self.lgNativeBlurRadiusOverride.doubleValue
            : LGNativeBlurRadiusForFilterType(_lgFilterType ?: wantType);

        if (!filterCls) { sblog("CAFilter class not found"); return; }

        id glassFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), wantType);

        if (!glassFilter) {
            LGLog(@"glass#%u filterWithType nil (not registered yet?)", _lgId);
            return;
        }

        if (LGNeedsGaussianIdentityFallback()) {
            @try { [glassFilter setValue:@1.0 forKey:@"inputRadius"]; }
            @catch (...) {}
        }

        layer.filters = @[glassFilter];
        _filterAttached = YES;

        [self updateNativeBlurOverlayWithRadius:blurRadius];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"LGLiveBackdropViewFilterDidAttach" object:self];
    } @catch (NSException *e) {
        sblog("applyFilters exception: %s", e.reason.UTF8String);
    }
}

- (void)reapplyFilterForParameterReload {

    _parameterRefreshVariant = !_parameterRefreshVariant;

    _appliedScale = -1.0;
    _filterAttached = NO;
    [self applyFilters];
    [self updateSpecular];
    [self.layer setNeedsDisplay];
    [_specularLayer setNeedsDisplay];
}

- (void)lgInvalidateFilterContents {
    _parameterRefreshVariant = !_parameterRefreshVariant;
    _filterAttached = NO;
    [self applyFilters];
    [self.layer setNeedsDisplay];
}

- (BOOL)lgFilterAttached {
    return _filterAttached;
}

@end

#pragma mark - generic host injection

static CGRect LGOutsetFrame(CGRect mf, UIEdgeInsets outset) {
    return CGRectMake(mf.origin.x - outset.left,
                      mf.origin.y - outset.top,
                      mf.size.width  + outset.left + outset.right,
                      mf.size.height + outset.top  + outset.bottom);
}

void LGInjectGlassIntoMaterialGroupType(UIView *mat, const void *assocKey,
                                        UIEdgeInsets outset, CGFloat cornerRadius,
                                        NSString *groupName, NSString *filterType) {
    UIView *parent = mat.superview;
    if (!parent) return;

    CGRect gf = LGOutsetFrame(mat.frame, outset);

    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) {
        glass = [[LGLiveBackdropView alloc] initWithFrame:gf groupName:groupName filterType:filterType];
        __weak LGLiveBackdropView *weakGlass = glass;
        for (NSNumber *delay in @[ @1.5, @3.0, @5.0, @8.0, @12.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakGlass applyFilters];
            });
        }
        [parent insertSubview:glass aboveSubview:mat];
        objc_setAssociatedObject(mat, assocKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != parent) [parent insertSubview:glass aboveSubview:mat];
    CGFloat radius = (cornerRadius >= 0.0) ? cornerRadius : mat.layer.cornerRadius;
    if (!CGRectEqualToRect(glass.frame, gf))          glass.frame              = gf;
    CGFloat shortest = fmin(CGRectGetWidth(gf), CGRectGetHeight(gf));
    if (shortest > 0.0 && radius >= (shortest * 0.5) - 1.5) {
        glass.layer.cornerCurve = kCACornerCurveCircular;
    } else {
        glass.layer.cornerCurve = kCACornerCurveContinuous;
    }
    glass.layer.masksToBounds = YES;
    if (fabs(glass.layer.cornerRadius - radius) > 0.5) {
        glass.layer.cornerRadius = radius;
        [glass updateSpecular];
        [glass applyFilters];
    } else {
        [glass updateSpecular];
    }

    objc_setAssociatedObject(glass, kLGOutsetKey, [NSValue valueWithUIEdgeInsets:outset],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, kLGRadiusKey, @(cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!mat.hidden) mat.hidden = YES;
}

static void LGSyncGlassGeometry(UIView *mat, const void *assocKey,
                                UIEdgeInsets outset, CGFloat cornerRadius);

void LGResyncGlassGeometry(UIView *mat, const void *assocKey) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) return;
    NSValue *ov  = objc_getAssociatedObject(glass, kLGOutsetKey);
    NSNumber *rv = objc_getAssociatedObject(glass, kLGRadiusKey);
    LGSyncGlassGeometry(mat, assocKey, ov ? ov.UIEdgeInsetsValue : UIEdgeInsetsZero,
                        rv ? rv.doubleValue : -1.0);
}

static void LGSyncGlassGeometry(UIView *mat, const void *assocKey,
                                UIEdgeInsets outset, CGFloat cornerRadius) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) return;
    CGRect gf = LGOutsetFrame(mat.frame, outset);
    CGFloat radius = (cornerRadius >= 0.0) ? cornerRadius : mat.layer.cornerRadius;

    if (!CGRectEqualToRect(glass.frame, gf)) {
        glass.frame = gf;
    }
    CGFloat shortest = fmin(CGRectGetWidth(gf), CGRectGetHeight(gf));
    if (shortest > 0.0 && radius >= (shortest * 0.5) - 1.5) {
        glass.layer.cornerCurve = kCACornerCurveCircular;
    } else {
        glass.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (fabs(glass.layer.cornerRadius - radius) > 0.5) {
        glass.layer.cornerRadius = radius;
        [glass updateSpecular];
        [glass applyFilters];
    } else {
        [glass updateSpecular];
    }
    if (!mat.hidden) mat.hidden = YES;
}

void LGRemoveGlassFromMaterial(UIView *mat, const void *assocKey) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) return;
    objc_setAssociatedObject(mat, assocKey, nil, OBJC_ASSOCIATION_ASSIGN);
    mat.hidden = NO;

    [glass removeFromSuperview];
}

BOOL LGMaterialHasGlass(UIView *mat, const void *assocKey) {
    return objc_getAssociatedObject(mat, assocKey) != nil;
}
