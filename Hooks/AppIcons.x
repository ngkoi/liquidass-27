#import <UIKit/UIKit.h>
#import <math.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

static void *kLGAppIconGlassKey = &kLGAppIconGlassKey;
static void *kLGAppIconCrossfadeKey = &kLGAppIconCrossfadeKey;
static void *kLGAppIconMorphingKey = &kLGAppIconMorphingKey;
static NSHashTable<LGLiveBackdropView *> *sLGAppIconGlasses;
static BOOL sLGAppIconLaunchTransition;
static NSUInteger sLGAppIconLaunchGeneration;

static BOOL LGIsAppIconImageView(UIView *view) {
    if (!view || !isExactClass(view, @"SBIconImageView")) return NO;
    if (fabs(CGRectGetWidth(view.bounds) - 60.0) > 0.5 ||
        fabs(CGRectGetHeight(view.bounds) - 60.0) > 0.5) return NO;

    UIView *parent = view.superview;
    UIView *grandparent = parent.superview;
    Class iconViewClass = NSClassFromString(@"SBIconView");
    return iconViewClass && grandparent && [grandparent isKindOfClass:iconViewClass];
}

static void LGRemoveAppIconGlass(UIView *iconView) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(iconView, kLGAppIconGlassKey);
    [glass removeFromSuperview];
    objc_setAssociatedObject(iconView, kLGAppIconGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static UIView *LGAppIconImageViewInView(UIView *view) {
    if (isExactClass(view, @"SBIconImageView")) return view;
    for (UIView *subview in view.subviews) {
        UIView *match = LGAppIconImageViewInView(subview);
        if (match) return match;
    }
    return nil;
}

static BOOL LGAppIconViewFlag(UIView *view, SEL selector) {
    if (![view respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))[view methodForSelector:selector])(view, selector);
}

static BOOL LGAppIconShouldRender(UIView *iconView) {
    if (!iconView || sLGAppIconLaunchTransition) return NO;
    if (LGAppIconViewFlag(iconView, @selector(isHighlighted)) ||
        LGAppIconViewFlag(iconView, @selector(isTouchDown)) ||
        LGAppIconViewFlag(iconView, @selector(isEditing))) return NO;
    return ![objc_getAssociatedObject(iconView, kLGAppIconCrossfadeKey) boolValue] &&
           ![objc_getAssociatedObject(iconView, kLGAppIconMorphingKey) boolValue];
}

static void LGSetAppIconGlassRendering(LGLiveBackdropView *glass, BOOL enabled) {
    if (!glass) return;
    BOOL active = enabled && glass.window && lgHostEnabled(@"AppIcons");
    glass.hidden = !active;
    @try { [glass.layer setValue:@(active) forKey:@"enabled"]; }
    @catch (__unused NSException *exception) {}
}

static void LGInstallAppIconGlass(UIView *iconView) {
    if (!LGIsAppIconImageView(iconView) || !lgHostEnabled(@"AppIcons")) {
        LGRemoveAppIconGlass(iconView);
        return;
    }

    UIView *parent = iconView.superview;
    if (!parent) return;

    LGLiveBackdropView *glass = objc_getAssociatedObject(iconView, kLGAppIconGlassKey);
    BOOL created = NO;
    if (!glass) {
        glass = LGCreateRegisteredGlass(iconView.frame, nil, @"AppIcons");
        if (!glass) return;
        created = YES;
        glass.userInteractionEnabled = NO;
        glass.autoresizingMask = UIViewAutoresizingNone;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        objc_setAssociatedObject(iconView, kLGAppIconGlassKey,
                                 glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sLGAppIconGlasses) sLGAppIconGlasses = [NSHashTable weakObjectsHashTable];
        [sLGAppIconGlasses addObject:glass];
        lgTrackGlass(glass, @"AppIcons", nil);
    }

    if (glass.superview != parent) {
        [glass removeFromSuperview];
        [parent insertSubview:glass belowSubview:iconView];
    }
    if (!CGRectEqualToRect(glass.frame, iconView.frame)) glass.frame = iconView.frame;

    CGFloat radius = CGRectGetWidth(iconView.frame) * 0.225;
    if (created || fabs(glass.layer.cornerRadius - radius) > 0.01)
        glass.layer.cornerRadius = radius;

    UIView *host = parent.superview;
    LGSetAppIconGlassRendering(glass, !host || LGAppIconShouldRender(host));
}

static void LGRefreshAppIconViewGlass(UIView *iconView) {
    UIView *imageView = LGAppIconImageViewInView(iconView);
    if (!imageView) return;
    LGInstallAppIconGlass(imageView);
    LGLiveBackdropView *glass = objc_getAssociatedObject(imageView, kLGAppIconGlassKey);
    LGSetAppIconGlassRendering(glass, LGAppIconShouldRender(iconView));
}

static void LGSetAllAppIconGlassRendering(BOOL enabled) {
    for (LGLiveBackdropView *glass in sLGAppIconGlasses.allObjects) {
        UIView *iconView = glass.superview.superview;
        LGSetAppIconGlassRendering(glass,
            enabled && (!iconView || LGAppIconShouldRender(iconView)));
    }
}

%hook SBIconImageView

- (void)didMoveToWindow {
    %orig;
    LGInstallAppIconGlass((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    LGInstallAppIconGlass((UIView *)self);
}

%end

%hook SBIconView

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig;
    LGRefreshAppIconViewGlass((UIView *)self);
}

- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    LGRefreshAppIconViewGlass((UIView *)self);
}

- (void)setTouchDown:(BOOL)touchDown {
    %orig;
    LGRefreshAppIconViewGlass((UIView *)self);
}

- (void)setCrossfadeFraction:(CGFloat)fraction {
    %orig;
    objc_setAssociatedObject(self, kLGAppIconCrossfadeKey, @(fraction > 0.001),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LGRefreshAppIconViewGlass((UIView *)self);
}

- (void)setMorphingFraction:(CGFloat)fraction {
    %orig;
    objc_setAssociatedObject(self, kLGAppIconMorphingKey, @(fraction > 0.001),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LGRefreshAppIconViewGlass((UIView *)self);
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    %orig;
    LGRefreshAppIconViewGlass((UIView *)self);
}

- (void)setEditing:(BOOL)editing {
    %orig;
    LGRefreshAppIconViewGlass((UIView *)self);
}

%end

%hook SBHIconManager

- (void)iconTapped:(id)iconView {
    sLGAppIconLaunchTransition = YES;
    NSUInteger generation = ++sLGAppIconLaunchGeneration;
    LGSetAllAppIconGlassRendering(NO);
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != sLGAppIconLaunchGeneration) return;
        sLGAppIconLaunchTransition = NO;
        LGSetAllAppIconGlassRendering(YES);
    });
}

%end
