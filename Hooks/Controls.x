#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <float.h>
#import <string.h>
#import "../LiquidAssPrefs/LGPrefsLiquidSlider.h"
#import "../LiquidAssPrefs/LGPrefsLiquidSwitch.h"
#pragma clang diagnostic ignored "-Wunused-function"
#import "../Shared/LGSharedSupport.h"
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGFramework.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGLiquidMotion.h"
#import "../Shared/LGLensRectState.h"

static void *kLGSettingsSwitchOverlayKey = &kLGSettingsSwitchOverlayKey;
static void *kLGSettingsSliderOverlayKey = &kLGSettingsSliderOverlayKey;
static void *kLGSettingsSliderVisualHostKey = &kLGSettingsSliderVisualHostKey;
static void *kLGSettingsSegmentGlassKey = &kLGSettingsSegmentGlassKey;
static void *kLGSettingsBarButtonGlassKey = &kLGSettingsBarButtonGlassKey;
static void *kLGSettingsBackButtonKey = &kLGSettingsBackButtonKey;
static void *kLGSettingsStockBackStateKey = &kLGSettingsStockBackStateKey;
static BOOL gLGApplyingSettingsBarButtonTransform = NO;
static void *kLGLiquidAssEntryFooterKey = &kLGLiquidAssEntryFooterKey;
static void *kLGSettingsBarBackgroundStateKey =
    &kLGSettingsBarBackgroundStateKey;
static void *kLGNavigationBackgroundAncestorKey = &kLGNavigationBackgroundAncestorKey;
static void *kLGNavigationFadeRefreshPendingKey = &kLGNavigationFadeRefreshPendingKey;
static BOOL gLGSettingsControlsEnabled = NO;
static BOOL gLGTextButtonsEnabled = NO;
static BOOL gLGNavigationTopFadeEnabled = NO;
static BOOL gLGSwitchControlsEnabled = NO;
static BOOL gLGSliderControlsEnabled = NO;
static BOOL gLGSegmentControlsEnabled = NO;
static BOOL gLGControlsDiagnosticsEnabled = NO;



typedef NS_ENUM(NSUInteger, LGControlsDiagnosticKind) {
    LGControlsDiagnosticSwitch,
    LGControlsDiagnosticSlider,
    LGControlsDiagnosticKindCount,
};

typedef struct {
    NSUInteger calls;
    NSUInteger created;
    double totalMilliseconds;
    double maximumMilliseconds;
} LGControlsDiagnosticBucket;

static LGControlsDiagnosticBucket gLGControlsDiagnosticBuckets[LGControlsDiagnosticKindCount];
static CFTimeInterval gLGControlsDiagnosticWindowStart = 0.0;
static NSUInteger gLGControlsSliderTrackingCalls = 0;
static NSUInteger gLGControlsSliderOwnerMoves = 0;
static NSUInteger gLGControlsSliderOwnerLayouts = 0;
static NSUInteger gLGControlsSliderOverlayMoves = 0;
static NSUInteger gLGControlsSliderOverlayLayouts = 0;
static NSUInteger gLGControlsSliderVisualMoves = 0;
static NSUInteger gLGControlsSliderVisualLayouts = 0;
static NSUInteger gLGControlsSliderSetters = 0;
static NSUInteger gLGControlsSwitchMoves = 0;
static NSUInteger gLGControlsSwitchLayouts = 0;
static NSUInteger gLGControlsModernSwitchMoves = 0;
static NSUInteger gLGControlsModernSwitchLayouts = 0;
static NSUInteger gLGControlsModernSwitchAlphaSets = 0;

static void LGRecordControlsDiagnostic(LGControlsDiagnosticKind kind,
                                       CFTimeInterval started,
                                       BOOL created) {
    if (!gLGControlsDiagnosticsEnabled) return;
    double milliseconds = (CACurrentMediaTime() - started) * 1000.0;
    LGControlsDiagnosticBucket *bucket = &gLGControlsDiagnosticBuckets[kind];
    bucket->calls++;
    bucket->created += created ? 1 : 0;
    bucket->totalMilliseconds += milliseconds;
    bucket->maximumMilliseconds = MAX(bucket->maximumMilliseconds, milliseconds);
    CFTimeInterval now = CACurrentMediaTime();
    if (gLGControlsDiagnosticWindowStart == 0.0) gLGControlsDiagnosticWindowStart = now;
    if (now - gLGControlsDiagnosticWindowStart < 1.0) return;
    LGControlsDiagnosticBucket *sw = &gLGControlsDiagnosticBuckets[LGControlsDiagnosticSwitch];
    LGControlsDiagnosticBucket *sl = &gLGControlsDiagnosticBuckets[LGControlsDiagnosticSlider];
    LGLog(@"[GlobalControlsPerf] switch calls=%lu created=%lu total=%.2fms max=%.2fms; slider calls=%lu created=%lu total=%.2fms max=%.2fms tracking=%lu",
               (unsigned long)sw->calls, (unsigned long)sw->created,
               sw->totalMilliseconds, sw->maximumMilliseconds,
               (unsigned long)sl->calls, (unsigned long)sl->created,
               sl->totalMilliseconds, sl->maximumMilliseconds,
               (unsigned long)gLGControlsSliderTrackingCalls);
    LGLog(@"[GlobalControlsSources] switch move=%lu layout=%lu modernMove=%lu modernLayout=%lu modernAlpha=%lu; slider ownerMove=%lu ownerLayout=%lu overlayMove=%lu overlayLayout=%lu visualMove=%lu visualLayout=%lu setters=%lu",
               (unsigned long)gLGControlsSwitchMoves,
               (unsigned long)gLGControlsSwitchLayouts,
               (unsigned long)gLGControlsModernSwitchMoves,
               (unsigned long)gLGControlsModernSwitchLayouts,
               (unsigned long)gLGControlsModernSwitchAlphaSets,
               (unsigned long)gLGControlsSliderOwnerMoves,
               (unsigned long)gLGControlsSliderOwnerLayouts,
               (unsigned long)gLGControlsSliderOverlayMoves,
               (unsigned long)gLGControlsSliderOverlayLayouts,
               (unsigned long)gLGControlsSliderVisualMoves,
               (unsigned long)gLGControlsSliderVisualLayouts,
               (unsigned long)gLGControlsSliderSetters);
    memset(gLGControlsDiagnosticBuckets, 0, sizeof(gLGControlsDiagnosticBuckets));
    gLGControlsSliderTrackingCalls = 0;
    gLGControlsSliderOwnerMoves = gLGControlsSliderOwnerLayouts = 0;
    gLGControlsSliderOverlayMoves = gLGControlsSliderOverlayLayouts = 0;
    gLGControlsSliderVisualMoves = gLGControlsSliderVisualLayouts = 0;
    gLGControlsSliderSetters = 0;
    gLGControlsSwitchMoves = gLGControlsSwitchLayouts = 0;
    gLGControlsModernSwitchMoves = gLGControlsModernSwitchLayouts = 0;
    gLGControlsModernSwitchAlphaSets = 0;
    gLGControlsDiagnosticWindowStart = now;
}



static BOOL LGSettingsFeatureEnabled(void) {
    id settings = LGGlassPreferenceValue(@"SettingsControls.Enabled");

    return ![settings respondsToSelector:@selector(boolValue)] ||
           [settings boolValue];
}

static BOOL LGProcessIsExcludedFromGlobalControls(void) {
    id stored = LGGlassPreferenceValue(@"GlobalControls.Exclusions");
    id exclusions = stored ?: @"NewTerm\nFilza\nTikTok\nDiscord\ncom.spotify.client";
    return LGProcessMatchesExclusionList(exclusions);
}

static BOOL LGProcessIsExcludedFromNavigationBar(void) {
    id stored = LGGlassPreferenceValue(@"NavigationBar.Exclusions");
    if (!stored) stored = LGGlassPreferenceValue(@"GlobalControls.Exclusions");
    id exclusions = stored ?: @"NewTerm\nFilza\nTikTok\nDiscord\ncom.spotify.client";
    return LGProcessMatchesExclusionList(exclusions);
}

static void LGRefreshGlobalControlEnablement(void) {
    gLGSettingsControlsEnabled = LGSettingsFeatureEnabled();
    BOOL allowed = gLGSettingsControlsEnabled && !LGProcessIsExcludedFromGlobalControls();
    BOOL navigationAllowed = gLGSettingsControlsEnabled && !LGProcessIsExcludedFromNavigationBar();
    id topFade = LGGlassPreferenceValue(@"NavigationBar.TopFade.Enabled");
    gLGNavigationTopFadeEnabled = navigationAllowed &&
        (![topFade respondsToSelector:@selector(boolValue)] || [topFade boolValue]);
    gLGTextButtonsEnabled = navigationAllowed && lgHostEnabled(@"PrefsButton");
    gLGSwitchControlsEnabled = allowed && lgHostEnabled(@"PrefsSwitch");
    gLGSliderControlsEnabled = allowed && lgHostEnabled(@"PrefsSlider");
    gLGSegmentControlsEnabled = allowed && lgHostEnabled(@"PrefsSegment");
}

static const CGFloat kLGNavigationTopFadeBlurRadius = 14.0;
static const CGFloat kLGNavigationTopFadeTintAlpha = 0.80;
static const CGFloat kLGNavigationTopFadeTaper = 20.0;
static const NSUInteger kLGNavigationTopFadeStops = 21;

static CGFloat LGNavigationTopFadeAlpha(CGFloat position) {
    return 1.0 - position * position * (3.0 - 2.0 * position);
}

static UIColor *LGNavigationTopFadeTint(void) {
    SEL selector = NSSelectorFromString(@"groupTableViewBackgroundColor");
    if ([UIColor respondsToSelector:selector])
        return ((UIColor *(*)(Class, SEL))objc_msgSend)(UIColor.class, selector);
    if (@available(iOS 13.0, *)) return UIColor.systemGroupedBackgroundColor;
    return UIColor.whiteColor;
}

@interface LGNavigationTopFadeView : UIView
@end


@implementation LGNavigationTopFadeView {
    LGAdjustableBlurView *_blur;
    CAGradientLayer *_mask;
    CAGradientLayer *_tint;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    _blur = [[LGAdjustableBlurView alloc] initWithFrame:self.bounds
                                             blurRadius:kLGNavigationTopFadeBlurRadius];
    [self addSubview:_blur];
    _mask = [CAGradientLayer layer];
    _mask.startPoint = CGPointMake(0.5, 0.0);
    _mask.endPoint = CGPointMake(0.5, 1.0);
    NSMutableArray *locations = [NSMutableArray arrayWithCapacity:kLGNavigationTopFadeStops];
    NSMutableArray *maskColors = [NSMutableArray array];
    for (NSUInteger index = 0; index < kLGNavigationTopFadeStops; index++) {
        CGFloat position = index / (CGFloat)(kLGNavigationTopFadeStops - 1);
        CGFloat alpha = LGNavigationTopFadeAlpha(position);
        [locations addObject:@(position)];
        [maskColors addObject:(__bridge id)[UIColor.blackColor
            colorWithAlphaComponent:alpha].CGColor];
    }
    _mask.locations = locations;
    _mask.colors = maskColors;
    _blur.layer.mask = _mask;
    _tint = [CAGradientLayer layer];
    _tint.startPoint = _mask.startPoint;
    _tint.endPoint = _mask.endPoint;
    _tint.locations = _mask.locations;
    [self.layer addSublayer:_tint];
    [self lg_updateTint];
    return self;
}
- (void)lg_updateTint {
    UIColor *color = LGNavigationTopFadeTint();
    if (@available(iOS 13.0, *))
        color = [color resolvedColorWithTraitCollection:self.traitCollection];
    NSMutableArray *colors = [NSMutableArray array];
    for (NSUInteger index = 0; index < kLGNavigationTopFadeStops; index++) {
        CGFloat position = index / (CGFloat)(kLGNavigationTopFadeStops - 1);
        [colors addObject:(__bridge id)[color colorWithAlphaComponent:
            kLGNavigationTopFadeTintAlpha * LGNavigationTopFadeAlpha(position)].CGColor];
    }
    _tint.colors = colors;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!previous || previous.userInterfaceStyle != self.traitCollection.userInterfaceStyle)
        [self lg_updateTint];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _blur.frame = self.bounds;
    _mask.frame = self.bounds;
    _tint.frame = self.bounds;
}
@end

static UINavigationBar *LGNavigationBarInTree(UIView *root, UIView *skip) {
    for (UIView *subview in root.subviews) {
        if (subview == skip) continue;
        if ([subview isKindOfClass:UINavigationBar.class]) return (UINavigationBar *)subview;
        UINavigationBar *found = LGNavigationBarInTree(subview, skip);
        if (found) return found;
    }
    return nil;
}

static UINavigationBar *LGNavigationBarForWrapper(UIView *wrapper) {
    UIView *child = wrapper;
    for (UIView *node = wrapper; node; child = node, node = node.superview) {
        UINavigationBar *found = LGNavigationBarInTree(node, child);
        if (found && found.window == wrapper.window) return found;
    }
    return nil;
}

static UIView *LGNavigationBarDirectBackground(UINavigationBar *bar) {
    Class backgroundClass = NSClassFromString(@"_UIBarBackground");
    for (UIView *subview in bar.subviews)
        if (backgroundClass && [subview isKindOfClass:backgroundClass]) return subview;
    return nil;
}

static UIView *LGNavigationTopFadeForBar(UINavigationBar *bar) {
    Class fadeClass = NSClassFromString(@"LGNavigationTopFadeView");
    for (UIView *subview in bar.subviews)
        if (fadeClass && [subview isKindOfClass:fadeClass]) return subview;
    return nil;
}

static BOOL LGNavigationBarBackgroundIsAtTop(UIView *background) {
    UIWindow *window = background.window;
    if (!window) return NO;
    CGRect frame = [background convertRect:background.bounds toView:window];
    CGFloat top = CGRectGetMinY(window.bounds);
    return CGRectGetMinY(frame) <= top + 1.0 && CGRectGetMaxY(frame) > top;
}

static void LGMarkNavigationBackgroundAncestors(UIView *background) {
    for (UIView *view = background; view; view = view.superview)
        objc_setAssociatedObject(view, kLGNavigationBackgroundAncestorKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSArray<UIView *> *LGNavigationBarAnchoredBackgrounds(UINavigationBar *bar) {
    Class backgroundClass = NSClassFromString(@"_UIBarBackground");
    UIWindow *window = bar.window;
    if (!backgroundClass || !window) return @[];
    UIView *topBackground = LGNavigationBarDirectBackground(bar);
    if (!topBackground || !LGNavigationBarBackgroundIsAtTop(topBackground)) return @[];
    NSMutableArray<UIView *> *backgrounds = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:window.subviews];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:backgroundClass]) {
            [backgrounds addObject:view];
            LGMarkNavigationBackgroundAncestors(view);
        }
        [stack addObjectsFromArray:view.subviews];
    }
    NSMutableArray<UIView *> *anchored = [NSMutableArray arrayWithObject:topBackground];
    CGRect frame = [topBackground convertRect:topBackground.bounds toView:window];
    BOOL changed = YES;
    while (changed) {
        changed = NO;
        for (UIView *background in backgrounds) {
            if ([anchored containsObject:background]) continue;
            CGRect candidate = [background convertRect:background.bounds toView:window];
            BOOL overlapsHorizontally = CGRectGetMinX(candidate) < CGRectGetMaxX(frame) &&
                                        CGRectGetMaxX(candidate) > CGRectGetMinX(frame);
            BOOL touchesVertically = CGRectGetMinY(candidate) <= CGRectGetMaxY(frame) + 1.0 &&
                                     CGRectGetMaxY(candidate) >= CGRectGetMinY(frame) - 1.0;
            if (!overlapsHorizontally || !touchesVertically) continue;
            [anchored addObject:background];
            frame = CGRectUnion(frame, candidate);
            changed = YES;
        }
    }
    return anchored;
}

static CGRect LGNavigationBarTopBackgroundFrame(UINavigationBar *bar) {
    NSArray<UIView *> *anchored = LGNavigationBarAnchoredBackgrounds(bar);
    UIWindow *window = bar.window;
    if (!anchored.count || !window) return CGRectNull;
    CGRect result = CGRectNull;
    for (UIView *background in anchored) {
        CGRect frame = [background convertRect:background.bounds toView:window];
        result = CGRectIsNull(result) ? frame : CGRectUnion(result, frame);
    }
    return result;
}

static BOOL LGNavigationBarHasVisibleLargeTitle(UINavigationBar *bar) {
    Class titleClass = NSClassFromString(@"_UINavigationBarLargeTitleView");
    if (!bar || !titleClass) return NO;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:bar.subviews];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:titleClass]) {
            UIWindow *window = bar.window;
            if (!window) return NO;
            CGRect frame = [view convertRect:view.bounds toView:window];
            CGRect visibleFrame = CGRectIntersection(frame, window.bounds);
            return !view.hidden && view.alpha > 0.01 &&
                   !CGRectIsNull(visibleFrame) && CGRectGetHeight(visibleFrame) > 1.0;
        }
        [stack addObjectsFromArray:view.subviews];
    }
    return NO;
}

static void LGPositionNavigationTopFade(UINavigationBar *bar, UIView *fade) {
    UIView *background = LGNavigationBarDirectBackground(bar);
    if (!background || !fade) return;
    NSUInteger fadeIndex = [bar.subviews indexOfObjectIdenticalTo:fade];
    NSUInteger backgroundIndex = [bar.subviews indexOfObjectIdenticalTo:background];
    if (fade.superview != bar || fadeIndex != backgroundIndex + 1)
        [bar insertSubview:fade aboveSubview:background];
}

static void LGRevealNavigationTopFade(UIView *fade) {
    if (!fade || fade.alpha >= 0.999) return;
    [UIView animateWithDuration:0.2 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{ fade.alpha = 1.0; }
                     completion:nil];
}

static UIView *LGEnsureNavigationTopFadeForBar(UINavigationBar *bar, BOOL animated) {
    CGRect frame = LGNavigationBarTopBackgroundFrame(bar);
    if (CGRectIsNull(frame)) return nil;
    UIWindow *window = bar.window;
    if (!window) return nil;
    UIView *fade = LGNavigationTopFadeForBar(bar);
    BOOL animateFrame = animated && fade.superview == bar;
    if (!fade) {
        fade = [[LGNavigationTopFadeView alloc] initWithFrame:CGRectZero];
        fade.alpha = 0.0;
        fade.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleBottomMargin;
    }
    frame.size.height += kLGNavigationTopFadeTaper;
    CGRect targetFrame = [bar convertRect:frame fromView:window];
    if (animateFrame && !CGRectEqualToRect(fade.frame, targetFrame)) {
        [UIView animateWithDuration:0.2 delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionCurveEaseInOut
                         animations:^{ fade.frame = targetFrame; }
                         completion:nil];
    } else {
        fade.frame = targetFrame;
    }
    LGPositionNavigationTopFade(bar, fade);
    return fade;
}

static void LGHideNavigationBarBackground(UINavigationBar *bar);
static void LGUpdateNavigationTopFadeForBar(UINavigationBar *bar);
static void LGUpdateNavigationTopFadeForBarAnimated(UINavigationBar *bar, BOOL animated);

static void LGScheduleNavigationFadeRefresh(UIWindow *window) {
    if (!window || [objc_getAssociatedObject(window, kLGNavigationFadeRefreshPendingKey) boolValue])
        return;
    objc_setAssociatedObject(window, kLGNavigationFadeRefreshPendingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(window, kLGNavigationFadeRefreshPendingKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:window.subviews];
        while (stack.count) {
            UIView *view = stack.lastObject;
            [stack removeLastObject];
            if ([view isKindOfClass:UINavigationBar.class])
                LGUpdateNavigationTopFadeForBarAnimated((UINavigationBar *)view, YES);
            [stack addObjectsFromArray:view.subviews];
        }
    });
}

static void LGUpdateNavigationTopFade(UIView *wrapper) {
    LGUpdateNavigationTopFadeForBar(LGNavigationBarForWrapper(wrapper));
}

static void LGHideNavigationBarBackground(UINavigationBar *bar) {
    Class backgroundClass = NSClassFromString(@"_UIBarBackground");
    UIWindow *window = bar.window;
    if (!backgroundClass || !window) return;
    NSArray<UIView *> *anchored = LGNavigationBarAnchoredBackgrounds(bar);
    BOOL shouldHide = gLGNavigationTopFadeEnabled && anchored.count == 1 &&
                      !LGNavigationBarHasVisibleLargeTitle(bar);
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:window.subviews];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:backgroundClass]) {
            NSDictionary *original = objc_getAssociatedObject(view, kLGSettingsBarBackgroundStateKey);
            if (!shouldHide || ![anchored containsObject:view]) {
                if (original) {
                    view.hidden = [original[@"hidden"] boolValue];
                    view.alpha = [original[@"alpha"] doubleValue];
                    view.userInteractionEnabled = [original[@"interaction"] boolValue];
                    objc_setAssociatedObject(view, kLGSettingsBarBackgroundStateKey,
                                             nil, OBJC_ASSOCIATION_ASSIGN);
                }
            } else {
                if (!original)
                    objc_setAssociatedObject(view, kLGSettingsBarBackgroundStateKey,
                        @{@"hidden": @(view.hidden), @"alpha": @(view.alpha),
                          @"interaction": @(view.userInteractionEnabled)},
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                view.hidden = YES;
                view.alpha = 0.0;
                view.userInteractionEnabled = NO;
            }
        }
        [stack addObjectsFromArray:view.subviews];
    }
}

static void LGUpdateNavigationTopFadeForBarAnimated(UINavigationBar *bar, BOOL animated) {
    UIView *fade = LGNavigationTopFadeForBar(bar);
    NSArray<UIView *> *anchored = LGNavigationBarAnchoredBackgrounds(bar);
    if (!gLGNavigationTopFadeEnabled || anchored.count != 1) {
        [fade removeFromSuperview];
    } else {
        fade = LGEnsureNavigationTopFadeForBar(bar, animated);
        if (LGNavigationBarHasVisibleLargeTitle(bar))
            fade.alpha = 0.0;
        else
            LGRevealNavigationTopFade(fade);
    }
    LGHideNavigationBarBackground(bar);
}

static void LGUpdateNavigationTopFadeForBar(UINavigationBar *bar) {
    LGUpdateNavigationTopFadeForBarAnimated(bar, NO);
}

static BOOL LGInsideLiquidAssPrefs(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        NSBundle *bundle = [NSBundle bundleForClass:r.class];
        if ([bundle.bundleIdentifier isEqualToString:@"dylv.liquidassprefs"] ||
            [NSStringFromClass(r.class) hasPrefix:@"LG"]) return YES;
    }
    return NO;
}



static void LGHideStockControlContents(UIView *control, UIView *except) {
    for (UIView *subview in control.subviews)
        if (subview != except) subview.alpha = 0.0;
}

static void LGRemoveSettingsSwitchOverlay(UISwitch *owner) {
    UIView *overlay = objc_getAssociatedObject(owner, kLGSettingsSwitchOverlayKey);
    if (!overlay) return;
    [overlay removeFromSuperview];
    objc_setAssociatedObject(owner, kLGSettingsSwitchOverlayKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    for (UIView *subview in owner.subviews) subview.alpha = 1.0;
}

static BOOL LGViewTreeHasSpeechRateEndpoints(UIView *root);

static UISlider *LGSettingsSliderOwnerForVisualElement(UIView *view) {
    for (UIView *candidate = view; candidate; candidate = candidate.superview)
        if ([candidate isKindOfClass:UISlider.class]) return (UISlider *)candidate;
    return nil;
}

static void LGSetNativeSliderTreeSuppressed(UIView *view, BOOL preserve) {
    if (!view) return;
    view.hidden = NO;
    view.userInteractionEnabled = NO;
    view.alpha = preserve ? 1.0 : 0.0;
    for (UIView *subview in view.subviews) {
        BOOL preserveSubview = preserve || [subview isKindOfClass:UILabel.class];
        LGSetNativeSliderTreeSuppressed(subview, preserveSubview);
    }
}

static void LGSuppressNativeSliderContents(UISlider *owner,
                                           LGPrefsLiquidSlider *overlay) {
    UIView *visualHost = objc_getAssociatedObject(owner,
                                                   kLGSettingsSliderVisualHostKey);
    UIView *root = visualHost ?: owner;
    for (UIView *subview in root.subviews) {
        if (subview == overlay) continue;
        LGSetNativeSliderTreeSuppressed(subview,
            [subview isKindOfClass:UILabel.class]);
    }
}

static UIView *LGSettingsSliderOverlayContainer(UISlider *owner) {
    // mount outside the stock slider so value labels stay untouched
    UIView *start = owner.superview ?: owner;
    UIView *container = start;
    for (UIView *candidate = start; candidate; candidate = candidate.superview) {
        if ([candidate isKindOfClass:UIScrollView.class]) break;
        container = candidate;
    }
    return container;
}

static CGRect LGSettingsSliderOverlayFrame(UISlider *owner, UIView *container) {
    UIView *host = objc_getAssociatedObject(owner, kLGSettingsSliderVisualHostKey);
    CGRect contentFrame = CGRectNull;
    CGRect labelFrame = CGRectNull;
    for (UIView *subview in host.subviews) {
        if (CGRectIsEmpty(subview.bounds)) continue;
        CGRect frame = [subview convertRect:subview.bounds toView:container];
        if ([subview isKindOfClass:UILabel.class]) {
            labelFrame = CGRectIsNull(labelFrame) ? frame : CGRectUnion(labelFrame, frame);
        } else {
            contentFrame = CGRectIsNull(contentFrame) ? frame : CGRectUnion(contentFrame, frame);
        }
    }
    if (CGRectIsNull(contentFrame) || CGRectIsEmpty(contentFrame))
        contentFrame = [owner convertRect:owner.bounds toView:container];
    if (!CGRectIsNull(labelFrame)) {
        if (CGRectGetMinX(labelFrame) > CGRectGetMinX(contentFrame)) {
            CGFloat maximumX = CGRectGetMinX(labelFrame) - 6.0;
            if (maximumX > CGRectGetMinX(contentFrame))
                contentFrame.size.width = maximumX - CGRectGetMinX(contentFrame);
        } else if (CGRectGetMaxX(labelFrame) < CGRectGetMaxX(contentFrame)) {
            CGFloat minimumX = CGRectGetMaxX(labelFrame) + 6.0;
            if (minimumX < CGRectGetMaxX(contentFrame)) {
                CGFloat rightX = CGRectGetMaxX(contentFrame);
                contentFrame.origin.x = minimumX;
                contentFrame.size.width = rightX - minimumX;
            }
        }
    }
    return contentFrame;
}

static void LGInstallSettingsSwitch(UISwitch *owner) {
    if (!gLGSwitchControlsEnabled) {
        LGRemoveSettingsSwitchOverlay(owner);
        return;
    }
    if (!owner.window ||
        [owner isKindOfClass:LGPrefsLiquidSwitch.class] ||
        LGInsideLiquidAssPrefs(owner)) return;

    LGPrefsLiquidSwitch *overlay =
        objc_getAssociatedObject(owner, kLGSettingsSwitchOverlayKey);
    if (!overlay) {
        overlay = [[LGPrefsLiquidSwitch alloc] initWithFrame:owner.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                   UIViewAutoresizingFlexibleHeight;
        __weak UISwitch *weakOwner = owner;
        [overlay addAction:[UIAction actionWithHandler:^(UIAction *action) {
            UISwitch *strongOwner = weakOwner;
            LGPrefsLiquidSwitch *sender = (LGPrefsLiquidSwitch *)action.sender;
            if (!strongOwner) return;
            [strongOwner setOn:sender.isOn animated:NO];
            [strongOwner sendActionsForControlEvents:UIControlEventValueChanged];
        }] forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(owner, kLGSettingsSwitchOverlayKey, overlay,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [owner addSubview:overlay];
    }

    owner.clipsToBounds = NO;
    owner.layer.masksToBounds = NO;
    overlay.frame = CGRectMake(-8.0, 0.0,
                               CGRectGetWidth(owner.bounds) + 8.0,
                               CGRectGetHeight(owner.bounds));
    if (overlay.isOn != owner.isOn) [overlay setOn:owner.isOn animated:NO];
    overlay.enabled = owner.enabled;
    LGHideStockControlContents(owner, overlay);
    [owner bringSubviewToFront:overlay];
}

static BOOL LGSliderUsesStockArtwork(UISlider *slider) {
    static Class resizableImageClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        resizableImageClass = NSClassFromString(@"_UIResizableImage");
    });
    if (!resizableImageClass) return YES;
    UIImage *images[] = { slider.currentThumbImage,
                          slider.currentMinimumTrackImage,
                          slider.currentMaximumTrackImage };
    for (size_t i = 0; i < sizeof(images) / sizeof(images[0]); i++) {
        if (images[i] && ![images[i] isKindOfClass:resizableImageClass]) return NO;
    }
    UIColor *tints[] = { slider.thumbTintColor,
                         slider.minimumTrackTintColor,
                         slider.maximumTrackTintColor };
    for (size_t i = 0; i < sizeof(tints) / sizeof(tints[0]); i++) {
        if (tints[i] && CGColorGetAlpha(tints[i].CGColor) < 0.01) return NO;
    }
    return YES;
}

static void LGRemoveSettingsSliderOverlay(UISlider *owner) {
    LGPrefsLiquidSlider *overlay =
        objc_getAssociatedObject(owner, kLGSettingsSliderOverlayKey);
    if (!overlay) return;
    objc_setAssociatedObject(owner, kLGSettingsSliderOverlayKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    [overlay removeFromSuperview];
    UIView *visualHost = objc_getAssociatedObject(owner,
                                                  kLGSettingsSliderVisualHostKey);
    UIView *root = visualHost ?: owner;
    for (UIView *subview in root.subviews) {
        if (subview == overlay) continue;
        LGSetNativeSliderTreeSuppressed(subview, YES);
    }
}

static UIImageView *LGSegmentSelectionIndicator(UISegmentedControl *control) {
    CGFloat height = CGRectGetHeight(control.bounds);
    if (!(height > 0.0)) return nil;
    for (UIView *subview in control.subviews) {
        if (![subview isKindOfClass:UIImageView.class]) continue;
        if (subview.subviews.count) continue;
        if (CGRectGetHeight(subview.frame) <= height) continue;
        return (UIImageView *)subview;
    }
    return nil;
}

static const CGFloat kLGSegmentGlassOverheight = 5.0;
static CGFloat LGSegmentGlassHeight(UISegmentedControl *control) {
    return CGRectGetHeight(control.bounds) + kLGSegmentGlassOverheight;
}
static const NSTimeInterval kLGSegmentMorphDuration = 0.18;

@class LGSegmentMotionState;
static void LGSegmentSetGestureClipping(LGSegmentMotionState *state,
                                        UISegmentedControl *control,
                                        BOOL clipping);

static BOOL LGIsRTLControl(UIView *view) {
    if (@available(iOS 9.0, *)) {
        if (view && view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft)
            return YES;
        if ([UIView userInterfaceLayoutDirectionForSemanticContentAttribute:
                view ? view.semanticContentAttribute : UISemanticContentAttributeUnspecified] == UIUserInterfaceLayoutDirectionRightToLeft)
            return YES;
    }
    return [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

static const CGFloat kLGSegmentShapeScale = 0.70;
static NSArray<UIView *> *LGSegmentViews(UISegmentedControl *control) {
    NSMutableArray<UIView *> *segments = [NSMutableArray array];
    for (UIView *subview in control.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:@"UISegment"])
            [segments addObject:subview];
    }
    const BOOL isRTL = LGIsRTLControl(control);
    [segments sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMinX(a.frame), bx = CGRectGetMinX(b.frame);
        if (isRTL)
            return ax > bx ? NSOrderedAscending : (ax < bx ? NSOrderedDescending : NSOrderedSame);
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return segments;
}

static NSInteger LGSegmentIndexNearest(UISegmentedControl *control, CGFloat x) {
    NSArray<UIView *> *segments = LGSegmentViews(control);
    NSInteger best = NSNotFound;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < segments.count; i++) {
        CGFloat distance = fabs(CGRectGetMidX(segments[i].frame) - x);
        if (distance < bestDistance) { bestDistance = distance; best = (NSInteger)i; }
    }
    return best;
}

static CGFloat LGSegmentSpringStep(CGFloat current, CGFloat target,
                                   CGFloat *velocity, CGFloat response,
                                   CGFloat damping, CGFloat dt) {
    CGFloat remaining = fmin(fmax(dt, 0.0), 1.0 / 30.0);
    while (remaining > 0.0) {
        CGFloat step = fmin(remaining, 1.0 / 240.0);
        CGFloat omega = 2.0 * M_PI / response;
        CGFloat acceleration = (target - current) * omega * omega -
                               2.0 * damping * omega * (*velocity);
        *velocity += acceleration * step;
        current += *velocity * step;
        remaining -= step;
    }
    return current;
}

static const CGFloat kLGSegmentSpringResponse = 0.34;
static const CGFloat kLGSegmentSpringDamping  = 0.78;
static const CFTimeInterval kLGSegmentSpringEaseIn = 0.13;
static const CGFloat kLGSegmentSpringEaseFloor = 0.45;

@interface LGSegmentMotionState : NSObject
@property (nonatomic, weak) UISegmentedControl *control;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) CGFloat targetCenterX, targetWidth, targetHeight;
@property (nonatomic, assign) CGFloat renderedCenterX, renderedWidth, renderedHeight;
@property (nonatomic, assign) CGFloat velocityX, lastTouchX, gestureStartX;
@property (nonatomic, assign) BOOL dragged;
@property (nonatomic, assign) CGFloat centreVelocity, widthVelocity, heightVelocity;
@property (nonatomic, assign) CFTimeInterval settleStart;
@property (nonatomic, assign) CFTimeInterval lastTouchTime, lastFrameTime;
@property (nonatomic, strong) NSMutableArray<NSArray *> *clipState;
- (void)start;
- (void)stop;
@end

static void LGSegmentApplyRendered(LGSegmentMotionState *state);

@implementation LGSegmentMotionState
- (void)start {
    if (_displayLink) return;
    _lastFrameTime = CACurrentMediaTime();
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stop { [_displayLink invalidate]; _displayLink = nil; }
- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat dt = (CGFloat)MAX(now - _lastFrameTime, 1.0 / 120.0);
    _lastFrameTime = now;
    LGLiquidRenderedState current =
        LGLiquidRenderedStateMake(_renderedCenterX,
                                  CGSizeMake(_renderedWidth, _renderedHeight));
    LGLiquidRenderedState target =
        LGLiquidRenderedStateMake(_targetCenterX,
                                  CGSizeMake(_targetWidth, _targetHeight));
    if (_active) {
        current = LGLiquidRenderedStateStep(current, target, YES, dt);
        _centreVelocity = _widthVelocity = _heightVelocity = 0.0;
        _settleStart = 0.0;
    } else {
        if (_settleStart <= 0.0) _settleStart = now;
        CGFloat elapsed = (CGFloat)(now - _settleStart);
        CGFloat t = kLGSegmentSpringEaseIn > 0.0
            ? fmin(1.0, elapsed / kLGSegmentSpringEaseIn) : 1.0;
        CGFloat eased = t * t * (3.0 - 2.0 * t);            // smoothstep
        CGFloat ease = kLGSegmentSpringEaseFloor +
                       (1.0 - kLGSegmentSpringEaseFloor) * eased;
        CGFloat response = kLGSegmentSpringResponse / ease;

        current.centerX = LGSegmentSpringStep(current.centerX, target.centerX,
                                              &_centreVelocity, response,
                                              kLGSegmentSpringDamping, dt);
        current.width = LGSegmentSpringStep(current.width, target.width,
                                            &_widthVelocity, response,
                                            kLGSegmentSpringDamping, dt);
        current.height = LGSegmentSpringStep(current.height, target.height,
                                             &_heightVelocity, response,
                                             kLGSegmentSpringDamping, dt);
    }
    _renderedCenterX = current.centerX;
    _renderedWidth = current.width;
    _renderedHeight = current.height;
    LGSegmentApplyRendered(self);

    if (!_active &&
        fabs(_renderedCenterX - _targetCenterX) < 0.5 &&
        fabs(_renderedWidth - _targetWidth) < 0.5 &&
        fabs(_centreVelocity) < 12.0 && fabs(_widthVelocity) < 12.0) {
        UISegmentedControl *control = _control;
        UIView *glass =
            objc_getAssociatedObject(control, kLGSettingsSegmentGlassKey);
        UIImageView *indicator = LGSegmentSelectionIndicator(control);
        [self stop];
        [UIView animateWithDuration:kLGSegmentMorphDuration delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionCurveEaseIn
                         animations:^{
            glass.alpha = 0.0;
            indicator.alpha = 1.0;
        } completion:^(BOOL finished) {
            if (finished) glass.hidden = YES;
            LGSegmentSetGestureClipping(self, control, YES);
        }];
    }
}
@end

static const CGFloat kLGSegmentOverhang = 26.0;
static const CGFloat kLGSegmentOverhangSoftness = 48.0;

static CGFloat LGSegmentRubberBandedCenterX(CGFloat touchX, CGFloat minX, CGFloat maxX) {
    if (touchX < minX) {
        CGFloat over = minX - touchX;
        return minX - kLGSegmentOverhang * (1.0 - exp(-over / kLGSegmentOverhangSoftness));
    }
    if (touchX > maxX) {
        CGFloat over = touchX - maxX;
        return maxX + kLGSegmentOverhang * (1.0 - exp(-over / kLGSegmentOverhangSoftness));
    }
    return touchX;
}

static void LGSegmentSetGestureClipping(LGSegmentMotionState *state,
                                        UISegmentedControl *control,
                                        BOOL clipping) {
    if (!clipping) {
        state.clipState = [NSMutableArray array];
        for (UIView *ancestor = control; ancestor; ancestor = ancestor.superview) {
            BOOL clips = ancestor.clipsToBounds;
            BOOL masks = ancestor.layer.masksToBounds;
            if (clips || masks) {
                [state.clipState addObject:@[ancestor, @(clips), @(masks)]];
                ancestor.clipsToBounds = NO;
                ancestor.layer.masksToBounds = NO;
            }
            if ([ancestor isKindOfClass:UITableViewCell.class]) break;
        }
        return;
    }
    for (NSArray *entry in state.clipState) {
        UIView *ancestor = entry[0];
        ancestor.clipsToBounds = [entry[1] boolValue];
        ancestor.layer.masksToBounds = [entry[2] boolValue];
    }
    state.clipState = nil;
}

static void LGSegmentApplyRendered(LGSegmentMotionState *state) {
    UISegmentedControl *control = state.control;
    UIView *glass =
        objc_getAssociatedObject(control, kLGSettingsSegmentGlassKey);
    if (!control || !glass) return;

    CGRect frame = CGRectMake(state.renderedCenterX - state.renderedWidth * 0.5,
                              CGRectGetMidY(control.bounds) - state.renderedHeight * 0.5,
                              state.renderedWidth, state.renderedHeight);

    CGSize captureSize = CGSizeMake(CGRectGetWidth(frame) / kLGSegmentShapeScale,
                                    CGRectGetHeight(frame) / kLGSegmentShapeScale);

    CGPoint captureCentre = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    UIWindow *captureWindow = control.window;
    if (captureWindow) {
        CGPoint inWindow = [control convertPoint:captureCentre toView:captureWindow];
        CGFloat half = captureSize.width * 0.5;
        CGFloat minCentre = half;
        CGFloat maxCentre = CGRectGetWidth(captureWindow.bounds) - half;
        if (minCentre <= maxCentre) {
            CGFloat clamped = MAX(minCentre, MIN(maxCentre, inWindow.x));
            if (clamped != inWindow.x) {
                CGPoint back = [control convertPoint:CGPointMake(clamped, inWindow.y)
                                            fromView:captureWindow];
                captureCentre.x = back.x;
            }
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    glass.transform = CGAffineTransformIdentity;
    glass.bounds = CGRectMake(0.0, 0.0, captureSize.width, captureSize.height);
    glass.center = captureCentre;
    glass.layer.cornerRadius = MIN(captureSize.width, captureSize.height) * 0.5;
    glass.layer.masksToBounds = NO;
    glass.clipsToBounds = NO;
    {
        CGRect pillNow = [control convertRect:frame toView:glass];
        if ([glass isKindOfClass:LGLiveBackdropView.class]) {
            LGLiveBackdropView *backdrop = (LGLiveBackdropView *)glass;
            backdrop.lgShapeRect = pillNow;
            backdrop.lgShapeCornerRadius = CGRectGetHeight(pillNow) * 0.5;
        }
    }
    [CATransaction commit];

    CGRect pillInGlass = [control convertRect:frame toView:glass];
    LGLensRectWrite(LGLensRectSlotPrefsSegment, YES,
                    CGRectGetMinX(pillInGlass) / captureSize.width,
                    CGRectGetMinY(pillInGlass) / captureSize.height,
                    CGRectGetWidth(pillInGlass) / captureSize.width,
                    CGRectGetHeight(pillInGlass) / captureSize.height);
}

static LGSegmentMotionState *LGSegmentMotionStateFor(UISegmentedControl *control,
                                                     BOOL create) {
    static void *key = &key;
    LGSegmentMotionState *state = objc_getAssociatedObject(control, key);
    if (!state && create) {
        state = [LGSegmentMotionState new];
        state.control = control;
        objc_setAssociatedObject(control, key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void LGSegmentAttachGesture(UISegmentedControl *control);
@class LGSegmentMotionState;
static void LGSegmentPresentGlass(UISegmentedControl *control,
                                  LGSegmentMotionState *state);

static void LGInstallSettingsSegment(UISegmentedControl *control) {
    if (!gLGSegmentControlsEnabled) {
        UIView *glass = objc_getAssociatedObject(control, kLGSettingsSegmentGlassKey);
        [glass removeFromSuperview];
        objc_setAssociatedObject(control, kLGSettingsSegmentGlassKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        UIImageView *indicator = LGSegmentSelectionIndicator(control);
        indicator.alpha = 1.0;
        return;
    }
    if (!control.window ||
        (LGInsideLiquidAssPrefs(control) &&
         ![control.accessibilityIdentifier hasSuffix:@".SpecularMode"])) return;

    UIImageView *indicator = LGSegmentSelectionIndicator(control);
    if (!indicator) return;

    UIView *glass = objc_getAssociatedObject(control, kLGSettingsSegmentGlassKey);
    if (!glass) {
        LGLiveBackdropView *backdrop =
            LGCreateRegisteredGlass(CGRectZero, nil, @"PrefsSegment");
        if (!backdrop) return;
        backdrop.lgSpecularEnabledOverride = @NO;
        glass = backdrop;
        glass.userInteractionEnabled = NO;
        objc_setAssociatedObject(control, kLGSettingsSegmentGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (glass.superview != control || control.subviews.lastObject != glass) {
        [glass removeFromSuperview];
        [control addSubview:glass];
    }

    control.clipsToBounds = NO;
    control.layer.masksToBounds = NO;


    if (@available(iOS 13.0, *))
        glass.layer.cornerCurve = kCACornerCurveContinuous;

    LGSegmentAttachGesture(control);

    LGSegmentMotionState *state = LGSegmentMotionStateFor(control, YES);
    if (!state.displayLink) {
        CGRect frame = indicator.frame;
        frame = CGRectInset(frame, 0.0,
                            (CGRectGetHeight(frame) - LGSegmentGlassHeight(control)) * 0.5);
        glass.transform = CGAffineTransformIdentity;
        glass.bounds = CGRectMake(0.0, 0.0,
                                  CGRectGetWidth(frame) / kLGSegmentShapeScale,
                                  CGRectGetHeight(frame) / kLGSegmentShapeScale);
        glass.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        glass.layer.cornerRadius =
            MIN(CGRectGetWidth(glass.bounds), CGRectGetHeight(glass.bounds)) * 0.5;
        glass.hidden = YES;
        indicator.alpha = 1.0;
        LGLensRectWrite(LGLensRectSlotPrefsSegment, NO, 0.f, 0.f, 0.f, 0.f);
    }
}

static void LGSegmentBeginTracking(UISegmentedControl *control, CGPoint point) {
    LGInstallSettingsSegment(control);
    UIView *glass =
        objc_getAssociatedObject(control, kLGSettingsSegmentGlassKey);
    UIImageView *indicator = LGSegmentSelectionIndicator(control);
    if (!glass || !indicator) return;

    LGSegmentMotionState *state = LGSegmentMotionStateFor(control, YES);
    CGRect start = CGRectInset(indicator.frame, 0.0,
        (CGRectGetHeight(indicator.frame) - LGSegmentGlassHeight(control)) * 0.5);
    state.renderedCenterX = CGRectGetMidX(start);
    state.renderedWidth = CGRectGetWidth(start);
    state.renderedHeight = LGSegmentGlassHeight(control);
    state.targetCenterX = state.renderedCenterX;
    state.targetWidth = state.renderedWidth;
    state.targetHeight = LGSegmentGlassHeight(control);
    state.gestureStartX = point.x;
    state.lastTouchX = point.x;
    state.dragged = NO;
    state.lastTouchTime = CACurrentMediaTime();
    state.velocityX = 0.0;
    state.active = YES;

}

static void LGSegmentPresentGlass(UISegmentedControl *control,
                                  LGSegmentMotionState *state) {
    UIView *glass = objc_getAssociatedObject(control, kLGSettingsSegmentGlassKey);
    UIImageView *indicator = LGSegmentSelectionIndicator(control);
    if (!glass || !indicator || !glass.hidden) return;

    LGSegmentApplyRendered(state);
    LGSegmentSetGestureClipping(state, control, NO);
    [glass.layer removeAllAnimations];
    glass.hidden = NO;
    glass.alpha = 0.0;
    [UIView animateWithDuration:kLGSegmentMorphDuration delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        glass.alpha = 1.0;
        indicator.alpha = 0.0;
    } completion:nil];
    [state start];
}

static void LGSegmentContinueTracking(UISegmentedControl *control, CGPoint point) {
    LGSegmentMotionState *state = LGSegmentMotionStateFor(control, NO);
    if (!state.active) return;
    NSArray<UIView *> *segments = LGSegmentViews(control);
    if (!segments.count) return;

    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = MAX(now - state.lastTouchTime, 0.001);
    if (!state.dragged && fabs(point.x - state.gestureStartX) > 4.0) {
        state.dragged = YES;
        LGSegmentPresentGlass(control, state);
    }
    if (!state.dragged) return;   // still a tap, leave it to the stock control
    state.velocityX = LGLiquidFilteredVelocity(state.velocityX,
                                               (point.x - state.lastTouchX) / dt);
    state.lastTouchX = point.x;
    state.lastTouchTime = now;

    CGFloat x1 = CGRectGetMidX(segments.firstObject.frame);
    CGFloat x2 = CGRectGetMidX(segments.lastObject.frame);
    CGFloat minimum = MIN(x1, x2);
    CGFloat maximum = MAX(x1, x2);
    CGFloat width = CGRectGetWidth(segments.firstObject.frame);

    CGFloat allowance = kLGSegmentOverhang;
    UIWindow *window = control.window;
    if (window) {
        CGRect restLeft  = [control convertRect:CGRectMake(minimum - width * 0.5, 0.0,
                                                           width, 1.0) toView:window];
        CGRect restRight = [control convertRect:CGRectMake(maximum - width * 0.5, 0.0,
                                                           width, 1.0) toView:window];
        CGFloat roomLeft  = CGRectGetMinX(restLeft);
        CGFloat roomRight = CGRectGetWidth(window.bounds) - CGRectGetMaxX(restRight);
        allowance = MIN(allowance, MAX(0.0, MIN(roomLeft, roomRight)));
    }
    LGLiquidDragState drag = LGLiquidDragStateMake(
        point.x, minimum, maximum,
        CGSizeMake(width, LGSegmentGlassHeight(control)),
        state.velocityX, LGSegmentGlassHeight(control) * 0.8);
    CGFloat sharedBand = LGLiquidRubberBandedCenterX(point.x, minimum, maximum, 1.24);
    CGFloat banded = LGSegmentRubberBandedCenterX(point.x, minimum, maximum)
                   + (drag.centerX - sharedBand);
    state.targetCenterX = MAX(minimum - allowance,
                              MIN(maximum + allowance, banded));
    state.targetWidth = drag.width;
    state.targetHeight = drag.height;
    [state start];
}

static void LGSegmentEndTracking(UISegmentedControl *control, BOOL commit) {
    LGSegmentMotionState *state = LGSegmentMotionStateFor(control, NO);
    if (!state.active) return;
    NSArray<UIView *> *segments = LGSegmentViews(control);
    if (!segments.count) { state.active = NO; return; }

    if (!state.dragged) {
        state.active = NO;
        return;
    }

    NSInteger index = LGSegmentIndexNearest(control, state.renderedCenterX);
    if (index == NSNotFound) index = control.selectedSegmentIndex;
    if (commit && index != control.selectedSegmentIndex) {
        control.selectedSegmentIndex = index;
        [control sendActionsForControlEvents:UIControlEventValueChanged];
    }

    UIView *destination = segments[(NSUInteger)MAX(0, MIN(index, (NSInteger)segments.count - 1))];
    state.active = NO;
    state.targetCenterX = CGRectGetMidX(destination.frame);
    state.targetWidth = CGRectGetWidth(destination.frame);
    state.targetHeight = LGSegmentGlassHeight(control);
    [state start];
}

@interface LGSegmentGesture : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UISegmentedControl *control;
@end

@implementation LGSegmentGesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (void)lg_handle:(UILongPressGestureRecognizer *)recognizer {
    UISegmentedControl *control = self.control;
    if (!control || !gLGSegmentControlsEnabled) return;
    CGPoint point = [recognizer locationInView:control];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            LGSegmentBeginTracking(control, point);
            break;
        case UIGestureRecognizerStateChanged:
            LGSegmentContinueTracking(control, point);
            break;
        case UIGestureRecognizerStateEnded:
            LGSegmentEndTracking(control, YES);
            break;
        default:
            LGSegmentEndTracking(control, NO);
            break;
    }
}
@end

static void LGSegmentAttachGesture(UISegmentedControl *control) {
    static void *key = &key;
    if (objc_getAssociatedObject(control, key)) return;
    LGSegmentGesture *handler = [LGSegmentGesture new];
    handler.control = control;
    UILongPressGestureRecognizer *recognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:handler
                                                      action:@selector(lg_handle:)];
    recognizer.minimumPressDuration = 0.0;
    recognizer.cancelsTouchesInView = NO;
    recognizer.delaysTouchesBegan = NO;
    recognizer.delaysTouchesEnded = NO;
    recognizer.delegate = handler;
    [control addGestureRecognizer:recognizer];
    objc_setAssociatedObject(control, key, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LGInstallSettingsSlider(UISlider *owner) {
    if (!gLGSliderControlsEnabled) {
        LGRemoveSettingsSliderOverlay(owner);
        return;
    }
    if (!owner.window ||
        [owner isKindOfClass:LGPrefsLiquidSlider.class] ||
        LGInsideLiquidAssPrefs(owner)) return;
    if (!LGSliderUsesStockArtwork(owner)) {
        LGRemoveSettingsSliderOverlay(owner);
        return;
    }
    for (UIView *candidate = owner; candidate; candidate = candidate.superview) {
        if (LGViewTreeHasSpeechRateEndpoints(candidate)) return;
        if ([candidate isKindOfClass:UITableViewCell.class]) break;
    }

    LGPrefsLiquidSlider *overlay =
        objc_getAssociatedObject(owner, kLGSettingsSliderOverlayKey);
    if (!overlay) {
        overlay = [[LGPrefsLiquidSlider alloc] initWithFrame:CGRectZero];
        __weak UISlider *weakOwner = owner;
        [overlay addAction:[UIAction actionWithHandler:^(UIAction *action) {
            UISlider *strongOwner = weakOwner;
            LGPrefsLiquidSlider *sender = (LGPrefsLiquidSlider *)action.sender;
            if (!strongOwner) return;
            [strongOwner setValue:sender.value animated:NO];
            [strongOwner sendActionsForControlEvents:UIControlEventValueChanged];
        }] forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(owner, kLGSettingsSliderOverlayKey, overlay,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *container = LGSettingsSliderOverlayContainer(owner);
    if (overlay.superview != container) {
        [overlay removeFromSuperview];
        [container addSubview:overlay];
    }
    CGRect overlayFrame = LGSettingsSliderOverlayFrame(owner, container);
    if (!CGRectEqualToRect(overlay.frame, overlayFrame)) overlay.frame = overlayFrame;
    if (fabsf(overlay.minimumValue - owner.minimumValue) > FLT_EPSILON)
        overlay.minimumValue = owner.minimumValue;
    if (fabsf(overlay.maximumValue - owner.maximumValue) > FLT_EPSILON)
        overlay.maximumValue = owner.maximumValue;
    if (overlay.enabled != owner.enabled) overlay.enabled = owner.enabled;

    id specifier = nil;
    for (UIView *candidate = owner; candidate && !specifier;
         candidate = candidate.superview) {
        @try {
            if ([candidate respondsToSelector:NSSelectorFromString(@"specifier")])
                specifier = [candidate valueForKey:@"specifier"];
        } @catch (__unused NSException *exception) {}
    }
    BOOL segmented = NO;
    NSInteger segmentCount = 0;
    if (specifier) {
        @try {
            segmented = [[specifier propertyForKey:@"isSegmented"] boolValue] ||
                        [[specifier propertyForKey:@"locksToSegment"] boolValue] ||
                        [[specifier propertyForKey:@"snapsToSegment"] boolValue];
            segmentCount = [[specifier propertyForKey:@"segmentCount"] integerValue];
        } @catch (__unused NSException *exception) {}
    }
    float range = owner.maximumValue - owner.minimumValue;
    float roundedRange = roundf(range);
    if (segmented && segmentCount <= 0 &&
        fabsf(range - roundedRange) <= 0.001f &&
        roundedRange >= 1.0f && roundedRange <= 24.0f)
        segmentCount = (NSInteger)roundedRange;
    objc_setAssociatedObject(overlay, kLGPrefsSliderSegmentedKey, @(segmented),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(overlay, kLGPrefsSliderSegmentCountKey,
                             @(segmentCount), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIColor *minimumTint = segmented ? UIColor.clearColor :
        (owner.minimumTrackTintColor ?: owner.tintColor ?: UIColor.systemBlueColor);
    UIColor *maximumTint = segmented ? UIColor.clearColor : owner.maximumTrackTintColor;
    if (![overlay.minimumTrackTintColor isEqual:minimumTint])
        overlay.minimumTrackTintColor = minimumTint;
    if ((overlay.maximumTrackTintColor || maximumTint) &&
        ![overlay.maximumTrackTintColor isEqual:maximumTint])
        overlay.maximumTrackTintColor = maximumTint;

    CGRect track = [owner trackRectForBounds:owner.bounds];
    CGRect minThumb = [owner thumbRectForBounds:owner.bounds trackRect:track
                                          value:owner.minimumValue];
    CGRect maxThumb = [owner thumbRectForBounds:owner.bounds trackRect:track
                                          value:owner.maximumValue];
    CGPoint minimumCenter = [owner convertPoint:
        CGPointMake(CGRectGetMidX(minThumb), CGRectGetMidY(minThumb)) toView:container];
    CGPoint maximumCenter = [owner convertPoint:
        CGPointMake(CGRectGetMidX(maxThumb), CGRectGetMidY(maxThumb)) toView:container];
    minimumCenter = [overlay convertPoint:minimumCenter fromView:container];
    maximumCenter = [overlay convertPoint:maximumCenter fromView:container];
    NSArray *endpoints = @[ @(minimumCenter.x), @(maximumCenter.x) ];
    objc_setAssociatedObject(overlay, kLGPrefsSliderEndpointCentersKey, endpoints,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (segmented && segmentCount > 0) {
        NSMutableArray *centers = [NSMutableArray arrayWithCapacity:segmentCount + 1];
        for (NSInteger index = 0; index <= segmentCount; index++) {
            float value = owner.minimumValue +
                ((float)index / (float)segmentCount) * range;
            CGRect thumb = [owner thumbRectForBounds:owner.bounds trackRect:track
                                               value:value];
            CGPoint center = [owner convertPoint:
                CGPointMake(CGRectGetMidX(thumb), CGRectGetMidY(thumb)) toView:container];
            center = [overlay convertPoint:center fromView:container];
            [centers addObject:@(center.x)];
        }
        objc_setAssociatedObject(overlay, kLGPrefsSliderSegmentCentersKey, centers,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(overlay, kLGPrefsSliderSegmentCentersKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (fabsf(overlay.value - owner.value) > FLT_EPSILON)
        [overlay setValue:owner.value animated:NO];
    LGSuppressNativeSliderContents(owner, overlay);
    [container bringSubviewToFront:overlay];
}

static void LGColorSettingsBarButtonLabels(UIView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"_UIModernBarButton"] &&
        [view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        button.tintColor = UIColor.labelColor;
        [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        [button setTitleColor:UIColor.labelColor forState:UIControlStateHighlighted];
    }
    if ([view isKindOfClass:UILabel.class])
        ((UILabel *)view).textColor = UIColor.labelColor;
    for (UIView *subview in view.subviews)
        LGColorSettingsBarButtonLabels(subview);
}

static BOOL LGBarButtonContainsText(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) return YES;
    for (UIView *subview in view.subviews)
        if (LGBarButtonContainsText(subview)) return YES;
    return NO;
}

@interface LGSettingsBarButtonPhysicsView : LGButtonView
@property (nonatomic, weak) UIView *nativeButton;
@property (nonatomic, assign) CGPoint nativeContentOffset;
@property (nonatomic, assign) BOOL iconOnly;
@end

@implementation LGSettingsBarButtonPhysicsView
- (void)unclipHierarchy {
    self.clipsToBounds = NO;
    self.layer.masksToBounds = NO;
    for (UIView *view = self.superview; view; view = view.superview) {
        view.clipsToBounds = NO;
        view.layer.masksToBounds = NO;
    }
}

- (void)lg_updateGlowAtPoint:(CGPoint)point
                      shiftX:(CGFloat)shiftX
                      shiftY:(CGFloat)shiftY
                       width:(CGFloat)width
                      height:(CGFloat)height {
    CGFloat deltaX = point.x - shiftX - CGRectGetMidX(self.bounds);
    CGFloat deltaY = point.y - shiftY - CGRectGetMidY(self.bounds);
    CGFloat radius = MAX(0.0, height * 0.5 - 2.0);
    CGFloat straightWidth = MAX(0.0, width * 0.5 - height * 0.5);
    deltaY = MAX(-radius, MIN(deltaY, radius));
    CGFloat capX = deltaX < -straightWidth ? deltaX + straightWidth
                 : deltaX > straightWidth ? deltaX - straightWidth : 0.0;
    if (capX != 0.0) {
        CGFloat distance = hypot(capX, deltaY);
        if (distance > radius && distance > 0.001) {
            deltaX = copysign(straightWidth, deltaX) + capX / distance * radius;
            deltaY = deltaY / distance * radius;
        }
    }
    CGPoint target = CGPointMake(width * 0.5 + deltaX, height * 0.5 + deltaY);
    CGPoint current = self.innerGlowView.center;
    self.innerGlowView.center = CGPointMake(current.x + (target.x - current.x) * 0.20,
                                            current.y + (target.y - current.y) * 0.20);
}

- (void)updateGlowPositionWithTouchPoint:(CGPoint)point
                                  shiftX:(CGFloat)shiftX
                                  shiftY:(CGFloat)shiftY {
    [self lg_updateGlowAtPoint:point shiftX:shiftX shiftY:shiftY
                         width:CGRectGetWidth(self.bounds) * 1.10
                        height:CGRectGetHeight(self.bounds) * 1.10];
}

- (void)lg_transformNativeContent:(CGAffineTransform)transform {
    transform.tx += self.nativeContentOffset.x;
    transform.ty += self.nativeContentOffset.y;
    gLGApplyingSettingsBarButtonTransform = YES;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithArray:self.nativeButton.subviews];
    while (views.count) {
        UIView *view = views.lastObject;
        [views removeLastObject];
        if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class])
            view.transform = transform;
        else
            [views addObjectsFromArray:view.subviews];
    }
    gLGApplyingSettingsBarButtonTransform = NO;
}

- (void)handleTouchDownAtPoint:(CGPoint)point {
    if (self.iconOnly) {
        [super handleTouchDownAtPoint:point];
        [UIView animateWithDuration:0.18 delay:0
            usingSpringWithDamping:0.55 initialSpringVelocity:1.2
            options:UIViewAnimationOptionAllowUserInteraction |
                    UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self lg_transformNativeContent:CGAffineTransformMakeScale(1.10, 1.10)];
        } completion:nil];
        return;
    }
    [super handleTouchDownAtPoint:point];
    [UIView animateWithDuration:0.18 delay:0
        usingSpringWithDamping:0.55 initialSpringVelocity:1.2
        options:UIViewAnimationOptionAllowUserInteraction |
                UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self lg_transformNativeContent:CGAffineTransformMakeScale(1.10, 1.10)];
    } completion:nil];
}

- (void)handleTouchMovedToPoint:(CGPoint)point {
    if (self.iconOnly) {
        [super handleTouchMovedToPoint:point];
        [self lg_transformNativeContent:self.backgroundContainer.transform];
        return;
    }
    if (!self.isPressed) {
        [self handleTouchDownAtPoint:point];
        return;
    }

    CGFloat deltaX = point.x - self.touchStartPoint.x;
    CGFloat deltaY = point.y - self.touchStartPoint.y;
    CGFloat distance = hypot(deltaX, deltaY);
    CGFloat effect = 50.0 * (1.0 - 1.0 / (distance * 0.025 + 1.0));
    CGFloat effectX = distance > 0.001 ? deltaX / distance * effect : 0.0;
    CGFloat effectY = distance > 0.001 ? deltaY / distance * effect : 0.0;
    CGFloat stretchX = 1.10 * (1.0 + fabs(effectX) * 0.003);
    CGFloat stretchY = 1.10 * (1.0 + fabs(effectY) * 0.006);
    CGFloat shiftX = effectX * 0.5;
    CGFloat shiftY = effectY * 0.5;

    CGAffineTransform transform = CGAffineTransformConcat(
        CGAffineTransformMakeTranslation(shiftX, shiftY),
        CGAffineTransformMakeScale(stretchX, stretchY));
    self.backgroundContainer.transform = transform;
    [self lg_transformNativeContent:transform];
    [self lg_updateGlowAtPoint:point shiftX:shiftX shiftY:shiftY
                         width:CGRectGetWidth(self.bounds) * stretchX
                        height:CGRectGetHeight(self.bounds) * stretchY];
    CGFloat glowScale = 1.0 + MIN(distance * 0.002, 0.18);
    self.innerGlowView.transform = CGAffineTransformMakeScale(glowScale, glowScale);
    self.innerGlowView.alpha = MIN(0.22 + distance * 0.0004, 0.30);
}

- (void)handleTouchEnded {
    if (self.iconOnly) {
        [super handleTouchEnded];
        [UIView animateWithDuration:0.52 delay:0
            usingSpringWithDamping:0.44 initialSpringVelocity:1.8
            options:UIViewAnimationOptionAllowUserInteraction |
                    UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self lg_transformNativeContent:CGAffineTransformIdentity];
        } completion:nil];
        return;
    }
    [super handleTouchEnded];
    [UIView animateWithDuration:0.52 delay:0
        usingSpringWithDamping:0.44 initialSpringVelocity:1.8
        options:UIViewAnimationOptionAllowUserInteraction |
                UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self lg_transformNativeContent:CGAffineTransformIdentity];
    } completion:nil];
}
@end



static CGRect LGSettingsBarButtonGlassFrame(UIView *button, CGRect content,
                                            BOOL iconOnly) {
    CGFloat height = 44.0;
    if (iconOnly)
        return CGRectMake(round(CGRectGetMidX(content) - height * 0.5),
                          round(CGRectGetMidY(content) - height * 0.5),
                          height, height);
    CGFloat padding = 16.0;
    BOOL onLeft = CGRectGetMidX([button convertRect:button.bounds toView:button.window]) <
                  CGRectGetMidX(button.window.bounds);
    UINavigationBar *bar = nil;
    for (UIView *view = button.superview; view; view = view.superview)
        if ([view isKindOfClass:UINavigationBar.class]) {
            bar = (UINavigationBar *)view;
            break;
        }
    CGRect margins = bar ? [bar convertRect:bar.layoutMarginsGuide.layoutFrame toView:button]
                         : button.bounds;
    CGFloat width = CGRectGetWidth(button.bounds) + padding;
    CGFloat originX = onLeft ? CGRectGetMinX(margins) : CGRectGetMaxX(margins) - width;
    return CGRectMake(originX,
                      (CGRectGetHeight(button.bounds) - height) * 0.5,
                      width, height);
}

static UIView *LGSettingsDescendantNamed(UIView *root, NSString *name) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:name]) return subview;
        UIView *found = LGSettingsDescendantNamed(subview, name);
        if (found) return found;
    }
    return nil;
}

static CGRect LGSettingsBarButtonContentFrame(UIView *button) {
    CGRect content = CGRectNull;
    for (UIView *view in button.subviews)
        if ([NSStringFromClass(view.class) isEqualToString:@"_UIModernBarButton"]) {
            CGRect stableFrame = CGRectMake(view.center.x - CGRectGetWidth(view.bounds) * 0.5,
                                            view.center.y - CGRectGetHeight(view.bounds) * 0.5,
                                            CGRectGetWidth(view.bounds),
                                            CGRectGetHeight(view.bounds));
            content = CGRectUnion(content, stableFrame);
        }
    return content;
}

static void LGCenterSettingsBarButtonContent(UIView *button,
                                             LGSettingsBarButtonPhysicsView *glass,
                                             CGRect content) {
    glass.nativeContentOffset = CGPointMake(CGRectGetMidX(glass.frame) - CGRectGetMidX(content),
                                            CGRectGetMidY(glass.frame) - CGRectGetMidY(content));
    if (!glass.isPressed)
        [glass lg_transformNativeContent:CGAffineTransformIdentity];
}

static BOOL LGIsNavigationContentBarButton(UIView *button) {
    Class contentClass = NSClassFromString(@"_UINavigationBarContentView");
    return contentClass &&
        ([button.superview isKindOfClass:contentClass] ||
         [button.superview.superview isKindOfClass:contentClass]);
}

static void LGUpdateSettingsBarButtonGlass(UIView *button) {
    LGSettingsBarButtonPhysicsView *glass =
        objc_getAssociatedObject(button, kLGSettingsBarButtonGlassKey);
    BOOL settingsBackButton =
        [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"] &&
        LGSettingsDescendantNamed(button, @"_UIBackButtonMaskView");
    if (!gLGTextButtonsEnabled || !LGIsNavigationContentBarButton(button) ||
        settingsBackButton) {
        [glass removeFromSuperview];
        objc_setAssociatedObject(button, kLGSettingsBarButtonGlassKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    LGColorSettingsBarButtonLabels(button);
    CGRect content = LGSettingsBarButtonContentFrame(button);
    if (CGRectIsNull(content)) content = button.bounds;
    BOOL iconOnly = !LGBarButtonContainsText(button);
    if ([button respondsToSelector:NSSelectorFromString(@"setBackButtonMaskEnabled:")])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(button,
            NSSelectorFromString(@"setBackButtonMaskEnabled:"), NO);
    CGRect frame = LGSettingsBarButtonGlassFrame(button, content, iconOnly);
    if (!glass) {
        glass = [[LGSettingsBarButtonPhysicsView alloc]
            initWithFrame:frame
                    title:@""
               blurRadius:2.0];
        glass.nativeButton = button;
        glass.userInteractionEnabled = NO;
        glass.layer.zPosition = -1.0;
        [button insertSubview:glass atIndex:0];
        objc_setAssociatedObject(button, kLGSettingsBarButtonGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    glass.iconOnly = iconOnly;
    if (glass.isPressed)
        glass.frame = frame;
    else
        [glass updateLayoutWithFrame:frame];
    LGCenterSettingsBarButtonContent(button, glass, content);
    [button sendSubviewToBack:glass];
}

static BOOL LGViewTreeHasSpeechRateEndpoints(UIView *root) {
    NSInteger matches = 0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        NSString *label = view.accessibilityLabel.lowercaseString ?: @"";
        if ([label isEqualToString:@"increase speed"] ||
            [label isEqualToString:@"decrease speed"]) {
            matches++;
            if (matches >= 2) return YES;
        }
        [stack addObjectsFromArray:view.subviews];
    }
    return NO;
}

static void LGProfiledInstallSettingsSwitch(UISwitch *owner) {
    if (!gLGControlsDiagnosticsEnabled) {
        LGInstallSettingsSwitch(owner);
        return;
    }
    BOOL existed = objc_getAssociatedObject(owner, kLGSettingsSwitchOverlayKey) != nil;
    CFTimeInterval started = CACurrentMediaTime();
    LGInstallSettingsSwitch(owner);
    BOOL created = !existed && objc_getAssociatedObject(owner, kLGSettingsSwitchOverlayKey) != nil;
    LGRecordControlsDiagnostic(LGControlsDiagnosticSwitch, started, created);
    if (created)
        LGLog(@"[GlobalControlsCreate] switch owner=%s super=%s frame=%s",
                   NSStringFromClass(owner.class).UTF8String,
                   NSStringFromClass(owner.superview.class).UTF8String,
                   NSStringFromCGRect(owner.frame).UTF8String);
}

static void LGProfiledInstallSettingsSlider(UISlider *owner) {
    if (!gLGControlsDiagnosticsEnabled) {
        LGInstallSettingsSlider(owner);
        return;
    }
    BOOL existed = objc_getAssociatedObject(owner, kLGSettingsSliderOverlayKey) != nil;
    CFTimeInterval started = CACurrentMediaTime();
    LGInstallSettingsSlider(owner);
    LGPrefsLiquidSlider *overlay = objc_getAssociatedObject(owner, kLGSettingsSliderOverlayKey);
    BOOL created = !existed && overlay != nil;
    LGRecordControlsDiagnostic(LGControlsDiagnosticSlider, started, created);
    if (created)
        LGLog(@"[GlobalControlsCreate] slider owner=%s visual=%s super=%s frame=%s segmented=%d count=%ld",
                   NSStringFromClass(owner.class).UTF8String,
                   NSStringFromClass(((UIView *)objc_getAssociatedObject(owner, kLGSettingsSliderVisualHostKey)).class).UTF8String,
                   NSStringFromClass(owner.superview.class).UTF8String,
                   NSStringFromCGRect(owner.frame).UTF8String,
                   [objc_getAssociatedObject(overlay, kLGPrefsSliderSegmentedKey) boolValue],
                   (long)[objc_getAssociatedObject(overlay, kLGPrefsSliderSegmentCountKey) integerValue]);
}

static void LGProfiledLayoutSettingsSlider(UISlider *owner) {
    LGPrefsLiquidSlider *overlay =
        objc_getAssociatedObject(owner, kLGSettingsSliderOverlayKey);
    if (!overlay) {
        LGProfiledInstallSettingsSlider(owner);
        return;
    }
    CFTimeInterval started = gLGControlsDiagnosticsEnabled ? CACurrentMediaTime() : 0.0;

    if (gLGControlsDiagnosticsEnabled)
        LGRecordControlsDiagnostic(LGControlsDiagnosticSlider, started, NO);
}



%group LiquidAssGlobalNavigationChrome

%hook UIViewControllerWrapperView
- (void)didMoveToWindow {
    %orig;
    LGUpdateNavigationTopFade((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    LGUpdateNavigationTopFade((UIView *)self);
}
%end

%hook UINavigationBar
- (void)didMoveToWindow {
    %orig;
    LGUpdateNavigationTopFadeForBar((UINavigationBar *)self);
}
- (void)layoutSubviews {
    %orig;
    LGUpdateNavigationTopFadeForBar((UINavigationBar *)self);
}
%end

%hook UIView
- (void)setBounds:(CGRect)bounds {
    BOOL tracksNavigationBackground =
        [objc_getAssociatedObject(self, kLGNavigationBackgroundAncestorKey) boolValue];
    %orig;
    if (tracksNavigationBackground) LGScheduleNavigationFadeRefresh(self.window);
}
- (void)setFrame:(CGRect)frame {
    BOOL tracksNavigationBackground =
        [objc_getAssociatedObject(self, kLGNavigationBackgroundAncestorKey) boolValue];
    %orig;
    if (tracksNavigationBackground) LGScheduleNavigationFadeRefresh(self.window);
}
%end

%end

%group LiquidAssGlobalControls

static UISwitch *LGSettingsOwnerForModernSwitchElement(UIView *element) {
    for (UIView *candidate = element.superview; candidate;
         candidate = candidate.superview) {
        if ([candidate isKindOfClass:UISwitch.class])
            return (UISwitch *)candidate;
    }
    return nil;
}

static BOOL LGSettingsShouldSuppressModernSwitchElement(UIView *element) {
    UISwitch *owner = LGSettingsOwnerForModernSwitchElement(element);
    if (!owner || !gLGSwitchControlsEnabled) return NO;
    return [owner isKindOfClass:LGPrefsLiquidSwitch.class] ||
        objc_getAssociatedObject(owner, kLGSettingsSwitchOverlayKey) != nil;
}

static void LGSettingsSuppressModernSwitchElementIfNeeded(UIView *element) {
    if (LGSettingsShouldSuppressModernSwitchElement(element) && element.alpha != 0.0)
        element.alpha = 0.0;
}





%hook UISwitchModernVisualElement
- (void)didMoveToSuperview {
    %orig;
    if (gLGControlsDiagnosticsEnabled) gLGControlsModernSwitchMoves++;
    LGSettingsSuppressModernSwitchElementIfNeeded((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    if (gLGControlsDiagnosticsEnabled) gLGControlsModernSwitchMoves++;
    LGSettingsSuppressModernSwitchElementIfNeeded((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    if (gLGControlsDiagnosticsEnabled) gLGControlsModernSwitchLayouts++;
    LGSettingsSuppressModernSwitchElementIfNeeded((UIView *)self);
}
- (void)setAlpha:(CGFloat)alpha {
    if (gLGControlsDiagnosticsEnabled) gLGControlsModernSwitchAlphaSets++;
    BOOL suppress = LGSettingsShouldSuppressModernSwitchElement((UIView *)self);
    %orig(suppress ? 0.0 : alpha);
}
%end

%hook UISwitch
- (void)didMoveToWindow {
    %orig;
    if (gLGControlsDiagnosticsEnabled) gLGControlsSwitchMoves++;
    LGProfiledInstallSettingsSwitch((UISwitch *)self);
}
- (void)layoutSubviews {
    %orig;
    if (gLGControlsDiagnosticsEnabled) gLGControlsSwitchLayouts++;
    LGProfiledInstallSettingsSwitch((UISwitch *)self);
}
- (void)setOn:(BOOL)on animated:(BOOL)animated {
    %orig;
    LGPrefsLiquidSwitch *overlay =
        objc_getAssociatedObject(self, kLGSettingsSwitchOverlayKey);
    if (overlay && overlay.isOn != on) [overlay setOn:on animated:animated];
}
%end

%hook _UISlideriOSVisualElement
- (void)didMoveToWindow {
    %orig;
    UISlider *owner = LGSettingsSliderOwnerForVisualElement((UIView *)self);
    if (!owner || [owner isKindOfClass:LGPrefsLiquidSlider.class]) return;
    if (gLGControlsDiagnosticsEnabled) gLGControlsSliderVisualMoves++;
    objc_setAssociatedObject(owner, kLGSettingsSliderVisualHostKey, self,
                             OBJC_ASSOCIATION_ASSIGN);
    LGProfiledLayoutSettingsSlider(owner);
}
- (void)layoutSubviews {
    %orig;
    UISlider *owner = LGSettingsSliderOwnerForVisualElement((UIView *)self);
    if (!owner || [owner isKindOfClass:LGPrefsLiquidSlider.class]) return;
    if (gLGControlsDiagnosticsEnabled) gLGControlsSliderVisualLayouts++;
    objc_setAssociatedObject(owner, kLGSettingsSliderVisualHostKey, self,
                             OBJC_ASSOCIATION_ASSIGN);
    LGProfiledInstallSettingsSlider(owner);
}
%end

%hook UISegmentedControl
- (void)didMoveToWindow {
    %orig;
    LGInstallSettingsSegment((UISegmentedControl *)self);
}
- (void)layoutSubviews {
    %orig;
    LGInstallSettingsSegment((UISegmentedControl *)self);
}
- (void)setSelectedSegmentIndex:(NSInteger)index {
    %orig;
    LGInstallSettingsSegment((UISegmentedControl *)self);
}
%end

%hook UISlider
- (void)didMoveToWindow {
    %orig;
    if (gLGControlsDiagnosticsEnabled) {
        if ([self isKindOfClass:LGPrefsLiquidSlider.class]) gLGControlsSliderOverlayMoves++;
        else gLGControlsSliderOwnerMoves++;
    }
    if (![self isKindOfClass:LGPrefsLiquidSlider.class])
        LGProfiledLayoutSettingsSlider((UISlider *)self);
}
- (void)layoutSubviews {
    %orig;
    if (gLGControlsDiagnosticsEnabled) {
        if ([self isKindOfClass:LGPrefsLiquidSlider.class]) gLGControlsSliderOverlayLayouts++;
        else gLGControlsSliderOwnerLayouts++;
    }
    if (![self isKindOfClass:LGPrefsLiquidSlider.class])
        LGProfiledInstallSettingsSlider((UISlider *)self);
}
- (void)setValue:(float)value animated:(BOOL)animated {
    %orig;
    LGPrefsLiquidSlider *overlay =
        objc_getAssociatedObject(self, kLGSettingsSliderOverlayKey);
    if (overlay && fabsf(overlay.value - value) > FLT_EPSILON)
        [overlay setValue:value animated:animated];
}
- (void)setMinimumValue:(float)value {
    %orig;
    if (![self isKindOfClass:LGPrefsLiquidSlider.class]) {
        if (gLGControlsDiagnosticsEnabled) gLGControlsSliderSetters++;
        LGProfiledInstallSettingsSlider((UISlider *)self);
    }
}
- (void)setMaximumValue:(float)value {
    %orig;
    if (![self isKindOfClass:LGPrefsLiquidSlider.class]) {
        if (gLGControlsDiagnosticsEnabled) gLGControlsSliderSetters++;
        LGProfiledInstallSettingsSlider((UISlider *)self);
    }
}
- (void)setEnabled:(BOOL)enabled {
    %orig;
    if (![self isKindOfClass:LGPrefsLiquidSlider.class]) {
        if (gLGControlsDiagnosticsEnabled) gLGControlsSliderSetters++;
        LGProfiledInstallSettingsSlider((UISlider *)self);
    }
}
- (void)setMinimumTrackTintColor:(UIColor *)color {
    %orig;
    if (![self isKindOfClass:LGPrefsLiquidSlider.class]) {
        if (gLGControlsDiagnosticsEnabled) gLGControlsSliderSetters++;
        LGProfiledInstallSettingsSlider((UISlider *)self);
    }
}
- (void)setMaximumTrackTintColor:(UIColor *)color {
    %orig;
    if (![self isKindOfClass:LGPrefsLiquidSlider.class]) {
        if (gLGControlsDiagnosticsEnabled) gLGControlsSliderSetters++;
        LGProfiledInstallSettingsSlider((UISlider *)self);
    }
}
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL result = %orig;
    if (gLGControlsDiagnosticsEnabled)
        LGLog(@"[GlobalControlsTrack] begin class=%s overlay=%d super=%s frame=%s",
                   NSStringFromClass(self.class).UTF8String,
                   [self isKindOfClass:LGPrefsLiquidSlider.class],
                   NSStringFromClass(((UIView *)self).superview.class).UTF8String,
                   NSStringFromCGRect(((UIView *)self).frame).UTF8String);
    return result;
}
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL result = %orig;
    if (gLGControlsDiagnosticsEnabled) gLGControlsSliderTrackingCalls++;
    return result;
}
- (void)endTracking:(UITouch *)touch withEvent:(UIEvent *)event {
    %orig;
    if (gLGControlsDiagnosticsEnabled)
        LGLog(@"[GlobalControlsTrack] end class=%s overlay=%d value=%.4f",
                   NSStringFromClass(self.class).UTF8String,
                   [self isKindOfClass:LGPrefsLiquidSlider.class], self.value);
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    %orig;
    if (gLGControlsDiagnosticsEnabled)
        LGLog(@"[GlobalControlsTrack] cancel class=%s overlay=%d",
                   NSStringFromClass(self.class).UTF8String,
                   [self isKindOfClass:LGPrefsLiquidSlider.class]);
}
%end

%end



%group LiquidAssGlobalTextButtons

%hook _UIButtonBarButton
- (void)setBackButtonMaskEnabled:(BOOL)enabled {
    %orig(gLGTextButtonsEnabled &&
          objc_getAssociatedObject(self, kLGSettingsBarButtonGlassKey) ? NO : enabled);
}
- (void)didMoveToWindow {
    %orig;
    LGUpdateSettingsBarButtonGlass((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    LGUpdateSettingsBarButtonGlass((UIView *)self);
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = %orig;
    LGSettingsBarButtonPhysicsView *glass =
        objc_getAssociatedObject(self, kLGSettingsBarButtonGlassKey);
    if (tracking && glass) {
        CGPoint point = [touch locationInView:(UIView *)self];
        [glass handleTouchDownAtPoint:[(UIView *)self convertPoint:point toView:glass]];
    }
    return tracking;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = %orig;
    LGSettingsBarButtonPhysicsView *glass =
        objc_getAssociatedObject(self, kLGSettingsBarButtonGlassKey);
    if (glass) {
        CGPoint point = [touch locationInView:(UIView *)self];
        [glass handleTouchMovedToPoint:[(UIView *)self convertPoint:point toView:glass]];
    }
    return tracking;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    %orig;
    [(LGSettingsBarButtonPhysicsView *)objc_getAssociatedObject(
        self, kLGSettingsBarButtonGlassKey) handleTouchEnded];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    %orig;
    [(LGSettingsBarButtonPhysicsView *)objc_getAssociatedObject(
        self, kLGSettingsBarButtonGlassKey) handleTouchEnded];
}
%end

%hook UIButtonLabel
- (void)setTransform:(CGAffineTransform)transform {
    if (!gLGApplyingSettingsBarButtonTransform) {
        for (UIView *parent = ((UIView *)self).superview; parent; parent = parent.superview) {
            LGSettingsBarButtonPhysicsView *glass =
                objc_getAssociatedObject(parent, kLGSettingsBarButtonGlassKey);
            if (glass && !glass.isPressed) {
                transform.tx += glass.nativeContentOffset.x;
                transform.ty += glass.nativeContentOffset.y;
                break;
            }
        }
    }
    %orig(transform);
}
%end

%hook _UIModernBarButton
- (void)layoutSubviews {
    %orig;
    for (UIView *parent = ((UIView *)self).superview; parent; parent = parent.superview) {
        LGSettingsBarButtonPhysicsView *glass =
            objc_getAssociatedObject(parent, kLGSettingsBarButtonGlassKey);
        if (glass && !glass.isPressed) {
            [glass lg_transformNativeContent:CGAffineTransformIdentity];
            break;
        }
    }
}
- (void)setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    UIView *view = (UIView *)self;
    BOOL insideGlassButton = NO;
    for (UIView *parent = view.superview; parent; parent = parent.superview)
        if (objc_getAssociatedObject(parent, kLGSettingsBarButtonGlassKey)) {
            insideGlassButton = YES;
            break;
        }
    if (!insideGlassButton || !title.length) {
        %orig;
        return;
    }
    NSMutableAttributedString *fixed = [title mutableCopy];
    [fixed addAttribute:NSForegroundColorAttributeName value:UIColor.labelColor
                  range:NSMakeRange(0, fixed.length)];
    %orig(fixed, state);
}
- (void)setTintColor:(UIColor *)color {
    UIView *view = (UIView *)self;
    for (UIView *parent = view.superview; parent; parent = parent.superview)
        if (objc_getAssociatedObject(parent, kLGSettingsBarButtonGlassKey)) {
            %orig(UIColor.labelColor);
            return;
        }
    %orig;
}
%end


%end



static void LGRefreshVisibleGlobalControlsInView(UIView *view) {
    Class barButtonClass = NSClassFromString(@"_UIButtonBarButton");
    if (barButtonClass && [view isKindOfClass:barButtonClass]) {
        LGUpdateSettingsBarButtonGlass(view);
    } else if ([view isKindOfClass:UISwitch.class] &&
        ![view isKindOfClass:LGPrefsLiquidSwitch.class]) {
        LGInstallSettingsSwitch((UISwitch *)view);
    } else if ([view isKindOfClass:UISegmentedControl.class]) {
        LGInstallSettingsSegment((UISegmentedControl *)view);
    } else if ([view isKindOfClass:UISlider.class] &&
               ![view isKindOfClass:LGPrefsLiquidSlider.class]) {
        LGInstallSettingsSlider((UISlider *)view);
    }
    for (UIView *subview in view.subviews) {
        LGRefreshVisibleGlobalControlsInView(subview);
    }
}

%ctor {
    if (LGIsExcludedSystemProcess()) return;
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    LGRefreshGlobalControlEnablement();
    %init(LiquidAssGlobalNavigationChrome);
    %init(LiquidAssGlobalTextButtons);

    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    gLGControlsDiagnosticsEnabled = NO;
    LGLog(@"global controls ctor bundle=%s enabled=%d",
          bundleIdentifier.UTF8String, gLGSettingsControlsEnabled);
    %init(LiquidAssGlobalControls);

    lgObservePreferenceReload(^{
        LGRefreshGlobalControlEnablement();
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            LGRefreshVisibleGlobalControlsInView(window);
            LGScheduleNavigationFadeRefresh(window);
        }
        LGLog(@"global controls reload bundle=%s enabled=%d",
              bundleIdentifier.UTF8String, gLGSettingsControlsEnabled);
    });
}
