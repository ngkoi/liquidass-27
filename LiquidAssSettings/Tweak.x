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
static void *kLGSettingsBackButtonKey = &kLGSettingsBackButtonKey;
static void *kLGSettingsStockBackStateKey = &kLGSettingsStockBackStateKey;
static void *kLGLiquidAssEntryFooterKey = &kLGLiquidAssEntryFooterKey;
static BOOL gLGSettingsControlsEnabled = NO;
static BOOL gLGSwitchControlsEnabled = NO;
static BOOL gLGSliderControlsEnabled = NO;
static BOOL gLGSegmentControlsEnabled = NO;
static BOOL gLGControlsDiagnosticsEnabled = NO;

static id LGPreferenceSpecifierProperty(id specifier, NSString *key) {
    SEL selector = NSSelectorFromString(@"propertyForKey:");
    if (!specifier || ![specifier respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, NSString *))objc_msgSend)(specifier, selector, key);
}

static BOOL LGIsLiquidAssPreferenceLoaderCell(UITableViewCell *cell) {
    id specifier = nil;
    if ([cell respondsToSelector:NSSelectorFromString(@"specifier")]) {
        specifier = ((id (*)(id, SEL))objc_msgSend)(cell,
                                                    NSSelectorFromString(@"specifier"));
    }
    for (NSString *key in @[@"lazy-bundle", @"bundle", @"bundlePath"]) {
        id value = LGPreferenceSpecifierProperty(specifier, key);
        if ([[value description] containsString:@"LiquidAssPrefs"]) return YES;
    }

    NSString *title = cell.textLabel.text ?: LGPreferenceSpecifierProperty(specifier, @"label");
    id detail = LGPreferenceSpecifierProperty(specifier, @"detail");
    return [title isEqualToString:@"Liquid (Gl)ass"] &&
           [[detail description] containsString:@"LGPRootListController"];
}

static void LGUpdateLiquidAssEntryFooter(UITableViewCell *cell) {
    UILabel *footer = objc_getAssociatedObject(cell, kLGLiquidAssEntryFooterKey);
    if (!gLGSettingsControlsEnabled) {
        footer.hidden = YES;
        return;
    }
    if (!LGIsLiquidAssPreferenceLoaderCell(cell)) {
        footer.hidden = YES;
        return;
    }
    if (!footer) {
        footer = [[UILabel alloc] initWithFrame:CGRectZero];
        footer.text = @"dylv";
        footer.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightRegular];
        footer.textColor = UIColor.tertiaryLabelColor;
        footer.textAlignment = NSTextAlignmentRight;
        footer.userInteractionEnabled = NO;
        footer.accessibilityElementsHidden = YES;
        [cell.contentView addSubview:footer];
        objc_setAssociatedObject(cell, kLGLiquidAssEntryFooterKey, footer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    footer.hidden = NO;
    [cell.contentView bringSubviewToFront:footer];
    CGFloat width = MIN(120.0, CGRectGetWidth(cell.contentView.bounds) * 0.42);
    footer.frame = CGRectMake(CGRectGetWidth(cell.contentView.bounds) - width - 8.0,
                              CGRectGetHeight(cell.contentView.bounds) - 14.0,
                              width, 12.0);
}

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

static const CGFloat kLGSidebarBorderWidth = 2.0;
static const CGFloat kLGSidebarBorderAlpha = 0.65;
static const CGFloat kLGSidebarBorderWhiteDark = 0.32;
static const CGFloat kLGSidebarTintAlpha = 0.80;

static UIColor *LGSidebarBorderColor(UIView *view) {
    BOOL dark = view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return dark ? [UIColor colorWithWhite:kLGSidebarBorderWhiteDark
                                    alpha:kLGSidebarBorderAlpha]
                : [UIColor.whiteColor colorWithAlphaComponent:kLGSidebarBorderAlpha];
}

static UIColor *LGSidebarTintBaseColor(void) {
    UIColor *base = nil;
    SEL selector = NSSelectorFromString(@"tableCellGroupedBackgroundColor");
    if ([UIColor respondsToSelector:selector]) {
        base = ((UIColor *(*)(Class, SEL))objc_msgSend)(UIColor.class, selector);
    }
    if (!base) {
        if (@available(iOS 13.0, *)) base = UIColor.secondarySystemGroupedBackgroundColor;
    }
    return base ?: UIColor.whiteColor;
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

static void LGRefreshGlobalControlEnablement(void) {
    gLGSettingsControlsEnabled = LGSettingsFeatureEnabled();
    BOOL allowed = gLGSettingsControlsEnabled && !LGProcessIsExcludedFromGlobalControls();
    gLGSwitchControlsEnabled = allowed && lgHostEnabled(@"PrefsSwitch");
    gLGSliderControlsEnabled = allowed && lgHostEnabled(@"PrefsSlider");
    gLGSegmentControlsEnabled = allowed && lgHostEnabled(@"PrefsSegment");
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

static BOOL LGControllerContainsLiquidAssPrefs(UIViewController *controller) {
    if (!controller) return NO;
    if ([[NSBundle bundleForClass:controller.class].bundleIdentifier
         isEqualToString:@"dylv.liquidassprefs"] ||
        [NSStringFromClass(controller.class) hasPrefix:@"LG"]) return YES;
    for (UIViewController *child in controller.childViewControllers)
        if (LGControllerContainsLiquidAssPrefs(child)) return YES;
    return controller.presentedViewController &&
           LGControllerContainsLiquidAssPrefs(controller.presentedViewController);
}

static BOOL LGSettingsChromeEnabledForView(UIView *view) {
    if (gLGSettingsControlsEnabled) return YES;
    if (LGInsideLiquidAssPrefs(view)) return YES;
    return LGControllerContainsLiquidAssPrefs(view.window.rootViewController);
}

@interface LGSettingsBackButton : UIControl
@property (nonatomic, strong) LGButtonView *visual;
@property (nonatomic, weak) UINavigationController *navigationController;
@property (nonatomic, weak) UIView *stockButton;
@end

@implementation LGSettingsBackButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    _visual = [[LGButtonView alloc] initWithFrame:self.bounds
                                       symbolName:@"chevron.left"
                                       blurRadius:2.0];
    _visual.userInteractionEnabled = NO;
    [self addSubview:_visual];
    [self addTarget:self action:@selector(lg_pop)
        forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self.visual updateLayoutWithFrame:self.bounds];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = [super beginTrackingWithTouch:touch withEvent:event];
    if (tracking) [self.visual handleTouchDownAtPoint:[touch locationInView:self.visual]];
    return tracking;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = [super continueTrackingWithTouch:touch withEvent:event];
    [self.visual handleTouchMovedToPoint:[touch locationInView:self.visual]];
    return tracking;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self.visual handleTouchEnded];
    [super endTrackingWithTouch:touch withEvent:event];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self.visual handleTouchEnded];
    [super cancelTrackingWithEvent:event];
}
- (BOOL)lg_invokeView:(UIView *)view {
    if ([view isKindOfClass:UIControl.class] && ((UIControl *)view).allTargets.count) {
        [(UIControl *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        NSArray *targets = nil;
        @try { targets = [recognizer valueForKey:@"_targets"]; }
        @catch (__unused NSException *exception) {}
        for (id targetAction in targets) {
            id target = nil;
            NSString *actionName = nil;
            @try {
                target = [targetAction valueForKey:@"target"];
                actionName = [targetAction valueForKey:@"action"];
            } @catch (__unused NSException *exception) {}
            SEL action = NSSelectorFromString(actionName);
            if (target && action && [target respondsToSelector:action]) {
                ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
                return YES;
            }
        }
    }
    for (UIView *subview in view.subviews)
        if ([self lg_invokeView:subview]) return YES;
    return NO;
}
- (void)lg_pop {
    if (![self lg_invokeView:self.stockButton])
        [self.navigationController popViewControllerAnimated:YES];
}
@end

static UIView *LGSettingsDescendantNamed(UIView *root, NSString *name) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:name]) return subview;
        UIView *found = LGSettingsDescendantNamed(subview, name);
        if (found) return found;
    }
    return nil;
}

static void LGUpdateSettingsBackButton(UINavigationBar *bar) {
    if (!bar.window) return;
    BOOL insideLiquidAssPrefs = LGInsideLiquidAssPrefs(bar);
    UIView *content = nil;
    for (UIView *subview in bar.subviews)
        if ([NSStringFromClass(subview.class) isEqualToString:@"_UINavigationBarContentView"]) {
            content = subview;
            break;
        }
    if (!content) return;
    LGSettingsBackButton *installed =
        objc_getAssociatedObject(content, kLGSettingsBackButtonKey);
    if (!gLGSettingsControlsEnabled) {
        UIView *stock = installed.stockButton;
        NSDictionary *original = stock
            ? objc_getAssociatedObject(stock, kLGSettingsStockBackStateKey) : nil;
        if (stock && original) {
            stock.hidden = [original[@"hidden"] boolValue];
            stock.alpha = [original[@"alpha"] doubleValue];
            stock.userInteractionEnabled = [original[@"interaction"] boolValue];
            objc_setAssociatedObject(stock, kLGSettingsStockBackStateKey, nil,
                                     OBJC_ASSOCIATION_ASSIGN);
        }
        [installed removeFromSuperview];
        objc_setAssociatedObject(content, kLGSettingsBackButtonKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    UINavigationController *navigation = nil;
    for (UIResponder *responder = bar; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UINavigationController.class]) {
            navigation = (UINavigationController *)responder;
            break;
        }
    }
    if (!navigation || navigation.viewControllers.count <= 1 || !bar.backItem) {
        [installed removeFromSuperview];
        objc_setAssociatedObject(content, kLGSettingsBackButtonKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    NSString *navigationClass = NSStringFromClass(navigation.class);
    if (insideLiquidAssPrefs || LGControllerContainsLiquidAssPrefs(navigation) ||
        [[NSBundle bundleForClass:navigation.class].bundleIdentifier
            isEqualToString:@"dylv.liquidassprefs"] ||
        [navigationClass hasPrefix:@"LG"]) {
        [installed removeFromSuperview];
        objc_setAssociatedObject(content, kLGSettingsBackButtonKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIView *stock = nil;
    for (UIView *candidate in content.subviews)
        if ([NSStringFromClass(candidate.class) isEqualToString:@"_UIButtonBarButton"] &&
            LGSettingsDescendantNamed(candidate, @"_UIBackButtonMaskView")) {
            stock = candidate;
            break;
        }
    if (!stock) return;
    LGSettingsBackButton *button = installed;
    if (!button) {
        button = [[LGSettingsBackButton alloc] initWithFrame:CGRectMake(16, 0, 44, 44)];
        [content addSubview:button];
        objc_setAssociatedObject(content, kLGSettingsBackButtonKey, button,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.navigationController = navigation;
    button.stockButton = stock;
    if (!objc_getAssociatedObject(stock, kLGSettingsStockBackStateKey)) {
        objc_setAssociatedObject(
            stock, kLGSettingsStockBackStateKey,
            @{@"hidden": @(stock.hidden),
              @"alpha": @(stock.alpha),
              @"interaction": @(stock.userInteractionEnabled)},
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.frame = CGRectMake(floor(MAX(16.0, bar.safeAreaInsets.left + 8.0)),
                              floor(CGRectGetMidY(content.bounds) - 22.0), 44.0, 44.0);
    stock.hidden = YES;
    stock.alpha = 0.0;
    stock.userInteractionEnabled = NO;
    [content bringSubviewToFront:button];
}


static BOOL LGSettingsShouldModifyCell(UIView *cell) {
    Class segmentCell = NSClassFromString(@"PSSegmentTableCell");
    Class sliderCell = NSClassFromString(@"PSSliderTableCell");
    return !(segmentCell && [cell isKindOfClass:segmentCell]) &&
           !(sliderCell && [cell isKindOfClass:sliderCell]);
}

static void LGUpdateSettingsCell(UITableViewCell *cell) {
    if (!gLGSettingsControlsEnabled) return;
    UIEdgeInsets inset = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    cell.separatorInset = inset;
    cell.layoutMargins = inset;
    cell.preservesSuperviewLayoutMargins = NO;
    if (!LGSettingsShouldModifyCell(cell)) return;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:cell];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if (fabs(view.layer.cornerRadius - 10.0) <= 0.25 &&
            CGRectGetHeight(view.bounds) > 0.0)
            view.layer.cornerRadius = 27.0;
        [stack addObjectsFromArray:view.subviews];
    }
}


static const CGFloat kLGSidebarInset = 12.0;
static const CGFloat kLGSearchBarHeightScale = 1.25;
static const CGFloat kLGSearchFieldHeightScale = 1.30;
static const CGFloat kLGSearchFieldIconInset = 8.0;
static const CGFloat kLGSearchBarWidthScale = 0.9635;
static const CGFloat kLGSidebarCornerRadiusFallback = 24.0;
static const CGFloat kLGSidebarWidth = 340.0;
static const CGFloat kLGSettingsCellHeight = 52.0;

static CGFloat LGSidebarCornerRadius(UIView *view) {
    static CGFloat cached = -1.0;
    if (cached < 0.0) {
        cached = 0.0;
        UIScreen *screen = view.window.screen ?: UIScreen.mainScreen;
        @try {
            id value = [screen valueForKey:@"_displayCornerRadius"];
            if ([value respondsToSelector:@selector(doubleValue)])
                cached = [value doubleValue];
        } @catch (__unused NSException *exception) {}
    }
    return cached > 0.5 ? cached : kLGSidebarCornerRadiusFallback;
}
static const CGFloat kLGSidebarTopGap = 0.0;
static const CGFloat kLGSidebarBlurRadius = 24.0;
static const CGFloat kLGSidebarShadowOpacity = 0.12;
static const CGFloat kLGSidebarShadowRadius = 12.0;
static const CGFloat kLGSidebarShadowOffsetX = 3.0;
static void *kLGSidebarPanelKey = &kLGSidebarPanelKey;
static void *kLGSidebarLargeTitleKey = &kLGSidebarLargeTitleKey;

static void LGClearBackground(UIView *view) {
    if (!view) return;
    UIColor *clear = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0];
    if (![view.backgroundColor isEqual:clear]) view.backgroundColor = clear;
}

static UITableView *LGSidebarTableView(UIView *transitionView, BOOL clearing) {
    if (clearing) LGClearBackground(transitionView);
    for (UIView *wrapper in transitionView.subviews) {
        if (!isExactClass(wrapper, @"UIViewControllerWrapperView")) continue;
        if (clearing) LGClearBackground(wrapper);
        for (UIView *controllerView in wrapper.subviews) {
            if (clearing) LGClearBackground(controllerView);
            for (UIView *sub in controllerView.subviews) {
                if ([sub isKindOfClass:UITableView.class]) return (UITableView *)sub;
            }
        }
    }
    return nil;
}

static BOOL LGViewIsColumnContainer(UIView *view) {
    if (!isExactClass(view, @"UILayoutContainerView")) return NO;
    for (UIView *sub in view.subviews) {
        if (isExactClass(sub, @"UINavigationTransitionView")) return YES;
    }
    return NO;
}

static BOOL LGIsSettingsSidebarContainer(UIView *view) {
    if (!LGViewIsColumnContainer(view)) return NO;
    UIView *parent = view.superview;
    if (!isExactClass(parent, @"UILayoutContainerView")) return NO;

    BOOL sawOtherColumn = NO;
    for (UIView *sibling in parent.subviews) {
        if (sibling == view || !LGViewIsColumnContainer(sibling)) continue;
        sawOtherColumn = YES;
        if (CGRectGetWidth(sibling.bounds) <= CGRectGetWidth(view.bounds)) return NO;
    }
    return sawOtherColumn;
}

static void *kLGSidebarAppliedKey = &kLGSidebarAppliedKey;


static const CGFloat kLGSidebarPressScale = 1.01;
static const CGFloat kLGSidebarGlowDiameterScale = 2.2;
static const CGFloat kLGSidebarGlowAlpha = 0.05;
static const NSInteger kLGSidebarGlowTag = 3;
static void *kLGSidebarPressHandlerKey = &kLGSidebarPressHandlerKey;

@interface LGSidebarPressHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *panel;
@end

@implementation LGSidebarPressHandler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)lg_handlePress:(UILongPressGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.panel];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            [self lg_setGlowVisible:YES at:location];
            [self lg_setPressed:YES];
            break;
        case UIGestureRecognizerStateChanged:
            [self lg_moveGlowTo:location];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self lg_setGlowVisible:NO at:location];
            [self lg_setPressed:NO];
            break;
        default:
            break;
    }
}

- (void)lg_moveGlowTo:(CGPoint)point {
    UIView *container = self.panel;
    UIView *panel = objc_getAssociatedObject(container, kLGSidebarPanelKey);
    if (!panel) return;
    UIView *host = nil;
    for (UIView *sub in panel.subviews) {
        if (sub.tag == kLGSidebarGlowTag) { host = sub; break; }
    }
    CALayer *glow = host.layer.sublayers.firstObject;
    if (![glow isKindOfClass:CAGradientLayer.class]) return;

    CGPoint centre = [host convertPoint:point fromView:container];
    CGFloat diameter = CGRectGetWidth(panel.bounds) * kLGSidebarGlowDiameterScale;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    glow.frame = CGRectMake(centre.x - diameter * 0.5, centre.y - diameter * 0.5,
                            diameter, diameter);
    [CATransaction commit];
}

- (void)lg_setGlowVisible:(BOOL)visible at:(CGPoint)point {
    UIView *container = self.panel;
    UIView *panel = objc_getAssociatedObject(container, kLGSidebarPanelKey);
    if (!panel) return;
    UIView *host = nil;
    for (UIView *sub in panel.subviews) {
        if (sub.tag == kLGSidebarGlowTag) { host = sub; break; }
    }
    CAGradientLayer *glow = (CAGradientLayer *)host.layer.sublayers.firstObject;
    if (![glow isKindOfClass:CAGradientLayer.class]) return;

    if (visible) [self lg_moveGlowTo:point];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    CALayer *presentation = glow.presentationLayer;
    fade.fromValue = @(presentation ? presentation.opacity : glow.opacity);
    fade.toValue = @(visible ? 1.0 : 0.0);
    fade.duration = visible ? 0.16 : 0.34;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:
        visible ? kCAMediaTimingFunctionEaseOut : kCAMediaTimingFunctionEaseInEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    glow.opacity = visible ? 1.0f : 0.0f;
    [CATransaction commit];
    [glow addAnimation:fade forKey:@"lgSidebarGlow"];
}

- (void)lg_setPressed:(BOOL)pressed {
    UIView *panel = self.panel;
    if (!panel) return;
    CALayer *layer = panel.layer;

    CGFloat scale = pressed ? kLGSidebarPressScale : 1.0;
    CATransform3D target = CATransform3DMakeScale(scale, scale, 1.0);

    CALayer *presentation = layer.presentationLayer;
    CATransform3D from = presentation ? presentation.sublayerTransform
                                      : layer.sublayerTransform;

    CASpringAnimation *spring =
        [CASpringAnimation animationWithKeyPath:@"sublayerTransform"];
    spring.mass = pressed ? 0.7 : 0.9;
    spring.stiffness = pressed ? 420.0 : 300.0;
    spring.damping = pressed ? 26.0 : 13.0;
    spring.initialVelocity = pressed ? 0.4 : 0.0;
    spring.fromValue = [NSValue valueWithCATransform3D:from];
    spring.toValue = [NSValue valueWithCATransform3D:target];
    spring.duration = spring.settlingDuration;
    spring.removedOnCompletion = YES;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = target;
    [CATransaction commit];
    [layer addAnimation:spring forKey:@"lgSidebarPress"];
}

@end

static void LGEnsureSidebarPressGesture(UIView *container) {
    if (objc_getAssociatedObject(container, kLGSidebarPressHandlerKey)) return;
    LGSidebarPressHandler *handler = [LGSidebarPressHandler new];
    handler.panel = container;
    UILongPressGestureRecognizer *gesture =
        [[UILongPressGestureRecognizer alloc] initWithTarget:handler
                                                      action:@selector(lg_handlePress:)];
    gesture.minimumPressDuration = 0.0;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.delegate = handler;
    [container addGestureRecognizer:gesture];
    objc_setAssociatedObject(container, kLGSidebarPressHandlerKey, handler,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *LGEnsureSidebarPanel(UIView *container) {
    UIView *panel = objc_getAssociatedObject(container, kLGSidebarPanelKey);
    if (panel) return panel;

    panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.userInteractionEnabled = NO;
    panel.backgroundColor = UIColor.clearColor;
    panel.layer.masksToBounds = NO;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = (float)kLGSidebarShadowOpacity;
    panel.layer.shadowRadius = kLGSidebarShadowRadius;
    panel.layer.shadowOffset = CGSizeMake(kLGSidebarShadowOffsetX, 0.0);

    LGAdjustableBlurView *blur =
        [[LGAdjustableBlurView alloc] initWithFrame:CGRectZero
                                         blurRadius:kLGSidebarBlurRadius];
    blur.tag = 1;
    [panel addSubview:blur];

    UIView *tint = [[UIView alloc] initWithFrame:CGRectZero];
    tint.userInteractionEnabled = NO;
    tint.backgroundColor =
        [LGSidebarTintBaseColor() colorWithAlphaComponent:kLGSidebarTintAlpha];
    tint.tag = 2;
    [panel addSubview:tint];

    UIView *glowHost = [[UIView alloc] initWithFrame:CGRectZero];
    glowHost.userInteractionEnabled = NO;
    glowHost.backgroundColor = UIColor.clearColor;
    glowHost.tag = kLGSidebarGlowTag;
    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.type = kCAGradientLayerRadial;
    glow.startPoint = CGPointMake(0.5, 0.5);
    glow.endPoint = CGPointMake(1.0, 1.0);
    glow.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:kLGSidebarGlowAlpha].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:kLGSidebarGlowAlpha * 0.45].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    glow.locations = @[ @0.0, @0.45, @1.0 ];
    glow.opacity = 0.0f;
    [glowHost.layer addSublayer:glow];
    [panel addSubview:glowHost];

    [container insertSubview:panel atIndex:0];
    objc_setAssociatedObject(container, kLGSidebarPanelKey, panel,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return panel;
}

static void LGLayoutSidebarPanel(UIView *panel, CGRect frame) {
    if (!CGRectEqualToRect(panel.frame, frame)) panel.frame = frame;
    CGFloat radius = LGSidebarCornerRadius(panel);
    CGRect bounds = CGRectMake(0.0, 0.0, CGRectGetWidth(frame), CGRectGetHeight(frame));
    panel.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:bounds
                                   cornerRadius:radius].CGPath;
    for (UIView *sub in panel.subviews) {
        if (!CGRectEqualToRect(sub.frame, bounds)) sub.frame = bounds;

        if (fabs(sub.layer.cornerRadius - radius) > 0.01) {
            sub.layer.cornerRadius = radius;
            if (@available(iOS 13.0, *))
                sub.layer.cornerCurve = kCACornerCurveContinuous;
        }
        if (!sub.layer.masksToBounds) sub.layer.masksToBounds = YES;
    }
}

static BOOL LGViewIsInsideSidebar(UIView *view) {
    for (UIView *node = view; node; node = node.superview) {
        if ([objc_getAssociatedObject(node, kLGSidebarAppliedKey) boolValue]) return YES;
    }
    return NO;
}

@interface LGSidebarPillView : UIView
@end
@implementation LGSidebarPillView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = CGRectGetHeight(self.bounds) * 0.5;
    if (fabs(self.layer.cornerRadius - radius) > 0.01) {
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *))
            self.layer.cornerCurve = kCACornerCurveContinuous;
    }
}
@end

static void *kLGSidebarLabelColorKey = &kLGSidebarLabelColorKey;

static CGFloat LGSettingsCellHeightFor(__unused UIView *cell) {
    return kLGSettingsCellHeight;
}

static void LGClearSidebarCellBackground(UITableViewCell *cell) {
    if (!gLGSettingsControlsEnabled) return;
    if (!LGViewIsInsideSidebar((UIView *)cell)) return;
    UIColor *clear = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0];
    if (![cell.backgroundColor isEqual:clear]) cell.backgroundColor = clear;
    if (![cell.contentView.backgroundColor isEqual:clear])
        cell.contentView.backgroundColor = clear;
    if (cell.backgroundView && ![cell.backgroundView.backgroundColor isEqual:clear])
        cell.backgroundView.backgroundColor = clear;

    for (UIView *sub in cell.subviews) {
        if (![NSStringFromClass(sub.class)
                isEqualToString:@"_UITableViewCellSeparatorView"]) continue;
        if (!sub.hidden) sub.hidden = YES;
    }

    if (@available(iOS 13.0, *)) {
        if (![cell.selectedBackgroundView isKindOfClass:LGSidebarPillView.class]) {
            LGSidebarPillView *pill =
                [[LGSidebarPillView alloc] initWithFrame:cell.bounds];
            pill.backgroundColor = UIColor.systemGray5Color;
            cell.selectedBackgroundView = pill;
        }

    }

    UITableView *table = nil;
    for (UIView *node = cell.superview; node; node = node.superview) {
        if ([node isKindOfClass:UITableView.class]) { table = (UITableView *)node; break; }
    }
    NSIndexPath *indexPath = table ? [table indexPathForCell:cell] : nil;
    BOOL active = cell.selected || cell.highlighted ||
        (indexPath && [indexPath isEqual:table.indexPathForSelectedRow]);
    UIColor *labelColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.7];
    for (UIView *sub in cell.contentView.subviews) {
        if (![NSStringFromClass(sub.class) isEqualToString:@"UITableViewLabel"]) continue;
        UILabel *label = (UILabel *)sub;
        if (active) {
            if (!objc_getAssociatedObject(label, kLGSidebarLabelColorKey)) {
                objc_setAssociatedObject(label, kLGSidebarLabelColorKey,
                                         label.textColor ?: NSNull.null,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (![label.textColor isEqual:labelColor]) label.textColor = labelColor;
            if (![label.highlightedTextColor isEqual:labelColor])
                label.highlightedTextColor = labelColor;
        } else {
            id original = objc_getAssociatedObject(label, kLGSidebarLabelColorKey);
            if (original) {
                label.textColor = original == NSNull.null ? nil : original;
                objc_setAssociatedObject(label, kLGSidebarLabelColorKey, nil,
                                         OBJC_ASSOCIATION_ASSIGN);
            }
        }
    }
}

static void LGResetSettingsSidebar(UIView *container) {
    if (![objc_getAssociatedObject(container, kLGSidebarAppliedKey) boolValue]) return;
    objc_setAssociatedObject(container, kLGSidebarAppliedKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    for (UIView *sub in container.subviews) {
        if (!isExactClass(sub, @"UINavigationTransitionView")) continue;
        sub.layer.cornerRadius = 0.0;
        sub.layer.masksToBounds = NO;
        sub.layer.borderWidth = 0.0;
        sub.frame = container.bounds;
        UITableView *table = LGSidebarTableView(sub, NO);
        if (table) {
            table.backgroundColor = nil;
            table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        }
    }
    for (UIView *sub in container.subviews) {
        if (![sub isKindOfClass:UINavigationBar.class]) continue;
        UINavigationBar *bar = (UINavigationBar *)sub;
        NSNumber *original = objc_getAssociatedObject(bar, kLGSidebarLargeTitleKey);
        if (original) {
            if (@available(iOS 11.0, *)) bar.prefersLargeTitles = original.boolValue;
            objc_setAssociatedObject(bar, kLGSidebarLargeTitleKey, nil,
                                     OBJC_ASSOCIATION_ASSIGN);
        }
        for (UIView *child in sub.subviews) {
            if ([NSStringFromClass(child.class)
                    isEqualToString:@"_UINavigationBarLargeTitleView"]) child.hidden = NO;
        }
    }
    LGSidebarPressHandler *pressHandler =
        objc_getAssociatedObject(container, kLGSidebarPressHandlerKey);
    if (pressHandler) {
        for (UIGestureRecognizer *gesture in [container.gestureRecognizers copy]) {
            if (gesture.delegate == (id)pressHandler)
                [container removeGestureRecognizer:gesture];
        }
        objc_setAssociatedObject(container, kLGSidebarPressHandlerKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        [container.layer removeAnimationForKey:@"lgSidebarPress"];
        container.layer.sublayerTransform = CATransform3DIdentity;
    }
    [(UIView *)objc_getAssociatedObject(container, kLGSidebarPanelKey)
        removeFromSuperview];
    objc_setAssociatedObject(container, kLGSidebarPanelKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
}


static void *kLGSidebarProbeKey = &kLGSidebarProbeKey;

static void LGProbeAppend(NSMutableString *out, UIView *view, NSUInteger depth,
                          NSUInteger maxDepth) {
    if (depth > maxDepth) return;
    NSString *pad = [@"" stringByPaddingToLength:depth * 2
                                      withString:@" " startingAtIndex:0];
    [out appendFormat:@"\n%@%@ f=%@ hidden=%d alpha=%.2f clips=%d radius=%.1f bg=%@",
        pad, NSStringFromClass(view.class), NSStringFromCGRect(view.frame),
        view.hidden, view.alpha, view.clipsToBounds, view.layer.cornerRadius,
        view.backgroundColor ? @"set" : @"nil"];
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)view;
        [out appendFormat:@" | contentInset=%@ contentSize=%@ header=%@%@ separator=%ld",
            NSStringFromUIEdgeInsets(table.contentInset),
            NSStringFromCGSize(table.contentSize),
            table.tableHeaderView ? NSStringFromClass(table.tableHeaderView.class) : @"(nil)",
            table.tableHeaderView ? NSStringFromCGRect(table.tableHeaderView.frame) : @"",
            (long)table.separatorStyle];
    }
    if ([view isKindOfClass:UINavigationBar.class]) {
        UINavigationBar *bar = (UINavigationBar *)view;
        BOOL prefersLarge = NO;
        id searchController = nil;
        UINavigationItemLargeTitleDisplayMode mode = 0;
        if (@available(iOS 11.0, *)) {
            prefersLarge = bar.prefersLargeTitles;
            searchController = bar.topItem.searchController;
            mode = bar.topItem.largeTitleDisplayMode;
        }
        [out appendFormat:@" | title=%@ prefersLargeTitles=%d largeTitleMode=%ld searchController=%@",
            bar.topItem.title, prefersLarge, (long)mode,
            searchController ? NSStringFromClass([searchController class]) : @"(nil)"];
    }
    for (UIView *sub in view.subviews) LGProbeAppend(out, sub, depth + 1, maxDepth);
}

static void LGProbeSidebar(UIView *container) {
    if (!LGDebugLoggingEnabled() || !container.window) return;

    NSMutableString *signature = [NSMutableString string];
    [signature appendFormat:@"%.0fx%.0f|", CGRectGetWidth(container.bounds),
                                           CGRectGetHeight(container.bounds)];
    for (UIView *child in container.subviews) {
        [signature appendFormat:@"%@(%lu)", NSStringFromClass(child.class),
                                (unsigned long)child.subviews.count];
    }
    NSString *previous = objc_getAssociatedObject(container, kLGSidebarProbeKey);
    if ([previous isEqualToString:signature]) return;
    objc_setAssociatedObject(container, kLGSidebarProbeKey, signature,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIWindow *window = container.window;
    NSMutableString *out = [NSMutableString stringWithFormat:
        @"[LGSIDEBARPROBE] ios=%@ idiom=%ld window=%@ safeArea=%@ scale=%.1f",
        UIDevice.currentDevice.systemVersion,
        (long)UIDevice.currentDevice.userInterfaceIdiom,
        NSStringFromCGRect(window.bounds),
        NSStringFromUIEdgeInsets(window.safeAreaInsets),
        window.screen.scale];

    for (UIResponder *responder = container; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UISplitViewController.class]) continue;
        UISplitViewController *split = (UISplitViewController *)responder;
        [out appendFormat:@"\n  split=%@ primary=%.1f min=%.1f max=%.1f collapsed=%d displayMode=%ld",
            NSStringFromClass(split.class), split.primaryColumnWidth,
            split.minimumPrimaryColumnWidth, split.maximumPrimaryColumnWidth,
            split.collapsed, (long)split.displayMode];
        break;
    }

    [out appendFormat:@"\n  --- sidebar container ---"];
    LGProbeAppend(out, container, 1, 6);

    [out appendString:@"\n  --- search ---"];
    for (NSString *name in @[@"PSKeyboardNavigationSearchBar",
                             @"PSKeyboardNavigationSearchController",
                             @"PSSearchController",
                             @"PSSearchResultsController"]) {
        [out appendFormat:@"\n    class %@ = %@", name,
            NSClassFromString(name) ? @"present" : @"ABSENT"];
    }

    for (UIResponder *responder = container; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        NSString *controllerName = NSStringFromClass(responder.class);
        if (![controllerName hasPrefix:@"PS"]) continue;
        for (NSString *key in @[@"spotlightSearchController", @"searchController"]) {
            if (![responder respondsToSelector:NSSelectorFromString(key)]) continue;
            id value = nil;
            @try { value = [responder valueForKey:key]; }
            @catch (__unused NSException *exception) { continue; }
            [out appendFormat:@"\n    %@.%@ = %@", controllerName, key,
                value ? NSStringFromClass([value class]) : @"(nil)"];
            if ([value isKindOfClass:UISearchController.class]) {
                UISearchBar *bar = ((UISearchController *)value).searchBar;
                [out appendFormat:@" searchBar=%@ f=%@ active=%d",
                    bar ? NSStringFromClass(bar.class) : @"(nil)",
                    bar ? NSStringFromCGRect(bar.frame) : @"",
                    ((UISearchController *)value).active];
            }
        }
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    NSUInteger found = 0;
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:view.subviews];

        NSString *viewName = NSStringFromClass(view.class);
        BOOL isSearchBar = [view isKindOfClass:UISearchBar.class] ||
                           [viewName containsString:@"SearchBar"];
        if (!isSearchBar) continue;
        found++;

        NSMutableString *chain = [NSMutableString string];
        for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview)
            [chain appendFormat:@"%@ < ", NSStringFromClass(ancestor.class)];

        CGSize fits = CGSizeZero;
        @try { fits = [view sizeThatFits:CGSizeMake(CGRectGetWidth(window.bounds), 0.0)]; }
        @catch (__unused NSException *exception) {}

        [out appendFormat:@"\n    [%lu] %@ f=%@ bounds=%@ hidden=%d alpha=%.2f",
            (unsigned long)found, viewName, NSStringFromCGRect(view.frame),
            NSStringFromCGRect(view.bounds), view.hidden, view.alpha];
        [out appendFormat:@"\n        sizeThatFits=%@ intrinsic=%@ translatesAutoresizing=%d constraints=%lu",
            NSStringFromCGSize(fits),
            NSStringFromCGSize(view.intrinsicContentSize),
            view.translatesAutoresizingMaskIntoConstraints,
            (unsigned long)view.constraints.count];
        [out appendFormat:@"\n        under: %@", chain];
        LGProbeAppend(out, view, 4, 7);
    }
    if (!found) [out appendString:@"\n    no search bar anywhere in the window"];

    LGLog(@"%@", out);
}

static void LGUpdateSettingsSidebar(UIView *container) {
    if (!LGIsSettingsSidebarContainer(container)) {
        if (LGViewIsColumnContainer(container)) LGResetSettingsSidebar(container);
        return;
    }
    objc_setAssociatedObject(container, kLGSidebarAppliedKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!container.window || !LGSettingsChromeEnabledForView(container)) return;

    UIView *page = container.superview;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIColor *pageColor = UIColor.groupTableViewBackgroundColor;
#pragma clang diagnostic pop
    if (![page.backgroundColor isEqual:pageColor]) page.backgroundColor = pageColor;

    container.clipsToBounds = NO;

    UIWindow *window = container.window;
    CGFloat safeTop = window.safeAreaInsets.top;
    CGFloat containerTop = [container convertPoint:CGPointZero toView:window].y;
    CGFloat top = MAX(kLGSidebarInset, safeTop - containerTop + kLGSidebarTopGap);

    LGProbeSidebar(container);
    LGEnsureSidebarPressGesture(container);

    for (UIView *sub in container.subviews) {
        if (![sub isKindOfClass:UINavigationBar.class]) continue;
        UINavigationBar *bar = (UINavigationBar *)sub;
        if (@available(iOS 11.0, *)) {
            if (!objc_getAssociatedObject(bar, kLGSidebarLargeTitleKey)) {
                objc_setAssociatedObject(bar, kLGSidebarLargeTitleKey,
                                         @(bar.prefersLargeTitles),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (bar.prefersLargeTitles) bar.prefersLargeTitles = NO;
            for (UINavigationItem *item in bar.items) {
                if (item.largeTitleDisplayMode != UINavigationItemLargeTitleDisplayModeNever)
                    item.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
            }
        }
        for (UIView *child in sub.subviews) {
            if (![NSStringFromClass(child.class)
                    isEqualToString:@"_UINavigationBarLargeTitleView"]) continue;
            if (!child.hidden) child.hidden = YES;
        }
    }

    CGRect bounds = container.bounds;
    CGRect inset = CGRectMake(CGRectGetMinX(bounds) + kLGSidebarInset,
                              CGRectGetMinY(bounds) + top,
                              CGRectGetWidth(bounds) - kLGSidebarInset * 2.0,
                              CGRectGetHeight(bounds) - top - kLGSidebarInset);
    for (UIView *sub in container.subviews) {
        if (!isExactClass(sub, @"UINavigationTransitionView")) continue;
        if (!CGRectEqualToRect(sub.frame, inset)) sub.frame = inset;
        CGFloat radius = LGSidebarCornerRadius(container);
        if (fabs(sub.layer.cornerRadius - radius) > 0.01) {
            sub.layer.cornerRadius = radius;
            if (@available(iOS 13.0, *))
                sub.layer.cornerCurve = kCACornerCurveContinuous;
        }
        if (!sub.layer.masksToBounds) sub.layer.masksToBounds = YES;

        UIColor *border = LGSidebarBorderColor(container);
        if (fabs(sub.layer.borderWidth - kLGSidebarBorderWidth) > 0.01)
            sub.layer.borderWidth = kLGSidebarBorderWidth;
        if (!CGColorEqualToColor(sub.layer.borderColor, border.CGColor))
            sub.layer.borderColor = border.CGColor;

        UITableView *sidebarTable = LGSidebarTableView(sub, YES);
        LGClearBackground(sidebarTable);
        if (sidebarTable.separatorStyle != UITableViewCellSeparatorStyleNone)
            sidebarTable.separatorStyle = UITableViewCellSeparatorStyleNone;
        LGLayoutSidebarPanel(LGEnsureSidebarPanel(container), inset);
    }
}



%group LiquidAssPreferencesChrome

%hook UINavigationBar
- (void)didMoveToWindow {
    %orig;
    LGUpdateSettingsBackButton((UINavigationBar *)self);
}
- (void)layoutSubviews {
    %orig;
    LGUpdateSettingsBackButton((UINavigationBar *)self);
}
%end

%end


%group LiquidAssPreferencesLayout

%hook PSTableCell
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize result = %orig;
    if (gLGSettingsControlsEnabled &&
        LGSettingsShouldModifyCell((UIView *)self) &&
        result.height >= 44.0 && result.height <= 55.0)
        result.height = LGSettingsCellHeightFor((UIView *)self);
    return result;
}
- (CGSize)systemLayoutSizeFittingSize:(CGSize)target
       withHorizontalFittingPriority:(UILayoutPriority)horizontal
             verticalFittingPriority:(UILayoutPriority)vertical {
    CGSize result = %orig;
    if (gLGSettingsControlsEnabled &&
        LGSettingsShouldModifyCell((UIView *)self) &&
        result.height >= 44.0 && result.height <= 55.0)
        result.height = LGSettingsCellHeightFor((UIView *)self);
    return result;
}
- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    %orig;
    LGClearSidebarCellBackground((UITableViewCell *)self);
}
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    BOOL sidebar = gLGSettingsControlsEnabled &&
                   LGViewIsInsideSidebar((UIView *)self);
    %orig(sidebar ? NO : highlighted, animated);
    LGClearSidebarCellBackground((UITableViewCell *)self);
}
- (void)layoutSubviews {
    %orig;
    LGUpdateSettingsCell((UITableViewCell *)self);
    LGClearSidebarCellBackground((UITableViewCell *)self);
    LGUpdateLiquidAssEntryFooter((UITableViewCell *)self);
}
%end

%hook PSSliderTableCell
- (void)layoutSubviews {
    %orig;
    if (gLGSettingsControlsEnabled)
        ((UIView *)self).layer.cornerRadius = 24.5;
}
%end


%hook UISplitViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!gLGSettingsControlsEnabled) return;

    CGFloat wanted = kLGSidebarWidth;
    if (self.minimumPrimaryColumnWidth > wanted)
        self.minimumPrimaryColumnWidth = wanted;
    if (fabs(self.maximumPrimaryColumnWidth - wanted) > 0.5)
        self.maximumPrimaryColumnWidth = wanted;
}

%end


@interface PSKeyboardNavigationSearchBar : UISearchBar
@end

%hook PSKeyboardNavigationSearchBar

- (void)setFrame:(CGRect)frame {
    if (gLGSettingsControlsEnabled && frame.size.width > 1.0 &&
        LGViewIsInsideSidebar((UIView *)self)) {
        CGFloat natural = frame.size.height;
        if (natural < 1.0) {
            natural = [self sizeThatFits:CGSizeMake(frame.size.width, 0.0)].height;
            if (natural < 1.0) natural = self.intrinsicContentSize.height;
        }
        if (natural > 1.0) frame.size.height = round(natural * kLGSearchBarHeightScale);
        CGFloat width = round(frame.size.width * kLGSearchBarWidthScale);
        frame.origin.x += round((frame.size.width - width) * 0.5);
        frame.size.width = width;
    }
    %orig(frame);
}

- (void)layoutSubviews {
    %orig;
    if (!gLGSettingsControlsEnabled || !LGViewIsInsideSidebar((UIView *)self)) return;

    if (!self.showsBookmarkButton) {
        UIImage *mic = nil;
        if (@available(iOS 13.0, *)) {
            for (NSString *name in @[@"microphone", @"mic"]) {
                mic = [UIImage systemImageNamed:name];
                if (mic) break;
            }
        }
        if (mic) {
            [self setImage:mic forSearchBarIcon:UISearchBarIconBookmark
                     state:UIControlStateNormal];
            self.showsBookmarkButton = YES;
        }
    }

    UIOffset leading = UIOffsetMake(kLGSearchFieldIconInset, 0.0);
    UIOffset trailing = UIOffsetMake(-kLGSearchFieldIconInset, 0.0);
    if (!UIOffsetEqualToOffset(
            [self positionAdjustmentForSearchBarIcon:UISearchBarIconSearch], leading)) {
        [self setPositionAdjustment:leading forSearchBarIcon:UISearchBarIconSearch];
    }
    if (self.showsBookmarkButton &&
        !UIOffsetEqualToOffset(
            [self positionAdjustmentForSearchBarIcon:UISearchBarIconBookmark], trailing)) {
        [self setPositionAdjustment:trailing forSearchBarIcon:UISearchBarIconBookmark];
    }
    if (!UIOffsetEqualToOffset(self.searchTextPositionAdjustment, leading)) {
        self.searchTextPositionAdjustment = leading;
    }

}

%end

@interface UISearchBarTextField : UITextField
@end

%hook UISearchBarTextField

- (void)setFrame:(CGRect)frame {
    if (gLGSettingsControlsEnabled && frame.size.height > 1.0 &&
        LGViewIsInsideSidebar((UIView *)self)) {
        CGFloat wanted = round(frame.size.height * kLGSearchFieldHeightScale);
        frame.origin.y -= round((wanted - frame.size.height) * 0.5);
        frame.size.height = wanted;
    }
    %orig(frame);
}

%end

@interface _UISearchBarSearchFieldBackgroundView : UIView
@end

%hook _UISearchBarSearchFieldBackgroundView

- (void)layoutSubviews {
    %orig;
    if (!gLGSettingsControlsEnabled || !LGViewIsInsideSidebar((UIView *)self)) return;
    CGFloat radius = CGRectGetHeight(self.bounds) * 0.5;
    if (radius < 0.5) return;
    if (fabs(self.layer.cornerRadius - radius) > 0.01) {
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *))
            self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (!self.layer.masksToBounds) self.layer.masksToBounds = YES;
}

%end

%hook UILayoutContainerView

- (void)layoutSubviews {
    %orig;
    LGUpdateSettingsSidebar((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    LGUpdateSettingsSidebar((UIView *)self);
}

%end

%end


%ctor {
    if (LGIsExcludedSystemProcess()) return;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"]) return;
    LGRefreshGlobalControlEnablement();
    %init(LiquidAssPreferencesChrome);
    %init(LiquidAssPreferencesLayout);
    lgObservePreferenceReload(^{ LGRefreshGlobalControlEnablement(); });
}
