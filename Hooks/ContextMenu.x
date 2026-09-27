#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

static const NSInteger kCtxDividerTag    = 0xD171;
static const CGFloat   kCtxCornerRadiusOffset = 5.0;
static const CGFloat   kCtxRowInset      = 16.0;
static const CGFloat   kCtxIconSize      = 20.0;
static const CGFloat   kCtxIconSpacing   = 12.0;
static const CGFloat   kCtxRowHeight     = 40.0;
static void *kCtxGlassKey         = &kCtxGlassKey;
static void *kCtxGapOriginalBgKey = &kCtxGapOriginalBgKey;
static void *kCtxOriginalAlphaKey = &kCtxOriginalAlphaKey;
static void *kCtxOriginalHiddenKey = &kCtxOriginalHiddenKey;
static void *kCtxOriginalRadiusKey = &kCtxOriginalRadiusKey;
static void *kCtxOriginalCurveKey = &kCtxOriginalCurveKey;
static void *kCtxOriginalMasksKey = &kCtxOriginalMasksKey;
static void *kCtxOriginalFrameKey = &kCtxOriginalFrameKey;
static void *kCtxOriginalContentModeKey = &kCtxOriginalContentModeKey;
static void *kCtxGlowViewKey = &kCtxGlowViewKey;
static void *kCtxCellPillKey = &kCtxCellPillKey;
static void *kCtxProbePendingKey = &kCtxProbePendingKey;
static void *kCtxGlassProbeKey = &kCtxGlassProbeKey;
static void *kCtxHierarchyProbeKey = &kCtxHierarchyProbeKey;
static void *kCtxOpenProbeKey = &kCtxOpenProbeKey;

@interface _UIContextMenuListView : UIView
@property (nonatomic, readonly) UICollectionView *collectionView;
@end

@interface _UIContextMenuView : UIView
@property (nonatomic, readonly) _UIContextMenuListView *currentListView;
@end

static void ctxRememberVisualState(UIView *view) {
    if (!view) return;
    if (!objc_getAssociatedObject(view, kCtxOriginalAlphaKey)) {
        objc_setAssociatedObject(view, kCtxOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kCtxOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kCtxOriginalRadiusKey, @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kCtxOriginalCurveKey, view.layer.cornerCurve ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(view, kCtxOriginalMasksKey, @(view.layer.masksToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ctxRememberFrame(UIView *view) {
    if (view && !objc_getAssociatedObject(view, kCtxOriginalFrameKey))
        objc_setAssociatedObject(view, kCtxOriginalFrameKey, [NSValue valueWithCGRect:view.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *findDescendantMatching(UIView *root, BOOL (^match)(UIView *v)) {
    for (UIView *sub in root.subviews) {
        if (match(sub)) return sub;
        UIView *found = findDescendantMatching(sub, match);
        if (found) return found;
    }
    return nil;
}

static BOOL isInsideContextMenu(UIView *v) {
    return hasAncestorOfClassName(v, @"_UIContextMenuContainerView") ||
           hasAncestorOfClassName(v, @"_UIContextMenuListView");
}

static BOOL ctxCellContextViewIsStock(UIView *view) {
    if (!isExactClass(view, @"_UIContextMenuCellContextView")) return NO;
    if (!isExactClass(view.superview, @"_UIContextMenuCell")) return NO;
    return findDescendantMatching(view, ^BOOL(UIView *c) {
        return [c isKindOfClass:[UIStackView class]];
    }) != nil;
}

static BOOL shouldRoundContextMenuSubview(UIView *view) {
    if ([view isKindOfClass:NSClassFromString(@"LGCtxMenuGlowView")] ||
        [view.superview isKindOfClass:NSClassFromString(@"LGCtxMenuGlowView")] ||
        [view isKindOfClass:NSClassFromString(@"LGCtxMenuPillView")]) return NO;
    if (isExactClass(view, @"_UIContextMenuCellContextView"))
        return ctxCellContextViewIsStock(view);
    CGSize s = view.bounds.size;
    return s.width >= 20.0 && s.height >= 20.0;
}

static CGFloat contextMenuCornerRadius(void) {
    return kCtxRowHeight * 0.5 + kCtxCornerRadiusOffset;
}

static void applyContextMenuRoundedStyle(UIView *view) {
    ctxRememberVisualState(view);
    CGFloat r = contextMenuCornerRadius();
    if (isExactClass(view, @"_UIContextMenuCellContentView") ||
        isExactClass(view, @"_UIContextMenuCellContextView")) {
        CGFloat pill = CGRectGetHeight(view.bounds) * 0.5;
        if (pill > 0.0) r = pill;
    }
    if (fabs(view.layer.cornerRadius - r) > 0.5) view.layer.cornerRadius = r;
    view.layer.cornerCurve = kCACornerCurveContinuous;
}

static BOOL shouldHideContextMenuSeparatorView(UIView *view) {
    if ([view isKindOfClass:[LGLiveBackdropView class]]) return NO;
    if (view.tag == kCtxDividerTag) return NO;
    if ([view isKindOfClass:[UIVisualEffectView class]]) return NO;
    NSString *cls = NSStringFromClass(view.class);
    if ([cls containsString:@"Separator"]) return YES;
    CGSize s = view.bounds.size;
    BOOL thinH = s.height > 0.0 && s.height <= 2.0 && s.width  >= 24.0;
    BOOL thinV = s.width  > 0.0 && s.width  <= 2.0 && s.height >= 24.0;
    return (thinH || thinV) && (view.backgroundColor || view.layer.backgroundColor);
}

static BOOL isContextMenuReusableGapView(UIView *view) {
    return isExactClass(view, @"UICollectionReusableView");
}

static UIColor *contextMenuDividerColor(UIView *view) {
    UITraitCollection *traits = view.traitCollection ?: UIScreen.mainScreen.traitCollection;
    if (traits.userInterfaceStyle == UIUserInterfaceStyleDark)
        return [UIColor colorWithWhite:1.0 alpha:0.16];
    return [UIColor colorWithWhite:0.0 alpha:0.10];
}

static void styleContextMenuReusableGapView(UIView *view) {
    ctxRememberVisualState(view);
    UIColor *bg = view.backgroundColor;
    if (bg && CGColorGetAlpha(bg.CGColor) > 0.001 &&
        !objc_getAssociatedObject(view, kCtxGapOriginalBgKey))
        objc_setAssociatedObject(view, kCtxGapOriginalBgKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = NO;
    view.alpha  = 1.0;
    view.backgroundColor = UIColor.clearColor;

    UIView *divider = [view viewWithTag:kCtxDividerTag];
    if (!divider) {
        divider = [[UIView alloc] initWithFrame:CGRectZero];
        divider.tag = kCtxDividerTag;
        divider.userInteractionEnabled = NO;
        [view addSubview:divider];
    }
    CGFloat inset = MAX(18.0, kCtxRowInset);
    CGFloat lineHeight = 2.0;
    CGFloat width = MAX(0.0, view.bounds.size.width - inset * 2.0);
    CGFloat y = round((view.bounds.size.height - lineHeight) * 0.5);
    divider.frame = CGRectMake(inset, y, width, lineHeight);
    divider.backgroundColor = contextMenuDividerColor(view);
    divider.layer.cornerRadius  = lineHeight * 0.5;
    divider.layer.masksToBounds = YES;

    for (UIView *inner in view.subviews) {
        if (inner == divider) continue;
        ctxRememberVisualState(inner);
        inner.hidden = YES;
        inner.alpha  = 0.0;
    }
}

static BOOL isContextMenuCutoutShadow(UIView *view) {
    return isExactClass(view, @"_UICutoutShadowView") &&
           isExactClass(view.superview, @"_UIContextMenuListView");
}

static void hideContextMenuSeparators(UIView *root) {
    for (UIView *sub in root.subviews) {
        if (shouldHideContextMenuSeparatorView(sub) ||
            isContextMenuCutoutShadow(sub)) {
            ctxRememberVisualState(sub);
            sub.hidden = YES;
            sub.alpha  = 0.0;
        } else if (isContextMenuReusableGapView(sub)) {
            styleContextMenuReusableGapView(sub);
        }
        hideContextMenuSeparators(sub);
    }
}

static void setBackdropHiddenInEffectView(UIView *effectView) {
    for (UIView *sub in effectView.subviews) {
        if ([sub isKindOfClass:[LGLiveBackdropView class]]) continue;
        if ([NSStringFromClass(sub.class) containsString:@"Backdrop"]) { ctxRememberVisualState(sub); sub.alpha = 0.0; return; }
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:[LGLiveBackdropView class]]) continue;
            if ([NSStringFromClass(inner.class) containsString:@"Backdrop"]) { ctxRememberVisualState(inner); inner.alpha = 0.0; return; }
        }
    }
}

static NSUInteger ctxGlassCount(UIView *root) {
    NSUInteger count = [root isKindOfClass:LGLiveBackdropView.class] ? 1 : 0;
    for (UIView *subview in root.subviews) count += ctxGlassCount(subview);
    return count;
}

static void injectGlassIntoContextEffectView(UIVisualEffectView *fx, int attempt) {
    if (!lgHostEnabled(@"ContextMenu")) return;
    if (isExactClass(fx.superview, @"_UIContextMenuHeaderView")) return;
    UIView *container = fx;
    while (container && !isExactClass(container, @"_UIContextMenuListView")) container = container.superview;
    if (!container) return;
    // springboard sometimes gives us zero-ish bounds for a bit
    if (CGRectGetWidth(container.bounds) < 10.0 || CGRectGetHeight(container.bounds) < 10.0) {
        if (attempt >= 10) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (fx.window) injectGlassIntoContextEffectView(fx, attempt + 1);
        });
        return;
    }

    LGLiveBackdropView *glass = objc_getAssociatedObject(container, kCtxGlassKey);
    BOOL created = !glass;
    if (!glass) {
        glass = LGCreateRegisteredGlass(container.bounds, nil, @"ContextMenu");
        if (!glass) return;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container insertSubview:glass atIndex:0];
        objc_setAssociatedObject(container, kCtxGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != container) [container insertSubview:glass atIndex:0];
    glass.frame                = container.bounds;
    glass.layer.cornerRadius   = contextMenuCornerRadius();
    glass.layer.cornerCurve    = kCACornerCurveContinuous;
    glass.layer.masksToBounds  = YES;
    if (created) [glass applyFilters];
    if (LGDebugLoggingEnabled() && ![objc_getAssociatedObject(fx, kCtxGlassProbeKey) boolValue]) {
        objc_setAssociatedObject(fx, kCtxGlassProbeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            objc_setAssociatedObject(fx, kCtxGlassProbeKey, nil, OBJC_ASSOCIATION_ASSIGN);
            LGLog(@"[ContextMenu glass] fx=%p %@ created=%d host=%p %@ hostFrame=%@ hostBounds=%@ glass=%p glassFrame=%@ glassCount=%lu",
                  fx, NSStringFromClass(fx.class), created, container, NSStringFromClass(container.class),
                  NSStringFromCGRect(container.frame), NSStringFromCGRect(container.bounds), glass,
                  NSStringFromCGRect(glass.frame), (unsigned long)ctxGlassCount(container));
        });
    }
}

static void removeGlassFromContextListView(UIView *listView) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(listView, kCtxGlassKey);
    if (!glass) return;
    [glass removeFromSuperview];
    objc_setAssociatedObject(listView, kCtxGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void relayoutContextMenuCellContent(UIView *contentView) {
    if (contentView.bounds.size.width < 40.0 || contentView.bounds.size.height < 20.0) return;

    UIImageView *iconView = (UIImageView *)findDescendantMatching(contentView, ^BOOL(UIView *v) {
        if (![v isKindOfClass:[UIImageView class]]) return NO;
        UIImageView *iv = (UIImageView *)v;
        return iv.image && iv.bounds.size.width > 8.0 && iv.bounds.size.height > 8.0;
    });
    UIView *textView = findDescendantMatching(contentView, ^BOOL(UIView *v) {
        if ([v isKindOfClass:[UIStackView class]]) {
            for (UIView *sub in v.subviews)
                if ([sub isKindOfClass:[UILabel class]]) return YES;
        }
        return [v isKindOfClass:[UILabel class]];
    });
    if (!textView || textView == (UIView *)iconView) return;

    if (!iconView) return;

    CGFloat iconY = round((contentView.bounds.size.height - kCtxIconSize) * 0.5);
    ctxRememberFrame(iconView);
    if (!objc_getAssociatedObject(iconView, kCtxOriginalContentModeKey))
        objc_setAssociatedObject(iconView, kCtxOriginalContentModeKey, @(iconView.contentMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(kCtxRowInset, iconY, kCtxIconSize, kCtxIconSize);

    CGRect textFrame = textView.frame;
    CGFloat textX    = kCtxRowInset + kCtxIconSize + kCtxIconSpacing;
    CGFloat maxWidth = contentView.bounds.size.width - textX - kCtxRowInset;
    if (maxWidth < 20.0) return;
    textFrame.origin.x   = textX;
    textFrame.size.width = maxWidth;
    ctxRememberFrame(textView);
    textView.frame = CGRectIntegral(textFrame);
}

@interface LGCtxMenuGlowView : UIView
@property (nonatomic, strong) CAGradientLayer *glowLayer;
- (void)moveToPoint:(CGPoint)point;
- (void)showAtPoint:(CGPoint)point;
- (void)hideGlow;
@end

@implementation LGCtxMenuGlowView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.cornerRadius = contextMenuCornerRadius();
        _glowLayer = [CAGradientLayer layer];
        _glowLayer.type = kCAGradientLayerRadial;
        _glowLayer.startPoint = CGPointMake(0.5, 0.5);
        _glowLayer.endPoint = CGPointMake(1.0, 1.0);
        _glowLayer.colors = @[
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.153].CGColor,
            (__bridge id)UIColor.clearColor.CGColor
        ];
        _glowLayer.locations = @[ @0.0, @0.45, @1.0 ];
        _glowLayer.opacity = 0.0f;
        [self.layer addSublayer:_glowLayer];
    }
    return self;
}
- (void)moveToPoint:(CGPoint)point {
    CGFloat diameter = CGRectGetWidth(self.bounds) * 1.15;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.glowLayer.frame = CGRectMake(point.x - diameter * 0.5, point.y - diameter * 0.5,
                                      diameter, diameter);
    [CATransaction commit];
}
- (void)showAtPoint:(CGPoint)point {
    [self moveToPoint:point];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    CALayer *presentation = self.glowLayer.presentationLayer;
    fade.fromValue = @(presentation ? presentation.opacity : self.glowLayer.opacity);
    fade.toValue = @1.0;
    fade.duration = 0.16;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.glowLayer.opacity = 1.0f;
    [CATransaction commit];
    [self.glowLayer addAnimation:fade forKey:@"contextMenuGlow"];
}
- (void)hideGlow {
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    CALayer *presentation = self.glowLayer.presentationLayer;
    fade.fromValue = @(presentation ? presentation.opacity : self.glowLayer.opacity);
    fade.toValue = @0.0;
    fade.duration = 0.34;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.glowLayer.opacity = 0.0f;
    [CATransaction commit];
    [self.glowLayer addAnimation:fade forKey:@"contextMenuGlow"];
}
@end

@interface LGCtxMenuPillView : UIView
@property (nonatomic) BOOL showing;
- (void)updateForBounds:(CGRect)bounds;
- (void)setShowing:(BOOL)showing animated:(BOOL)animated;
@end

@implementation LGCtxMenuPillView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.alpha = 0.0;
        self.hidden = YES;
    }
    return self;
}
- (void)updateForBounds:(CGRect)bounds {
    self.frame = CGRectInset(bounds, 6.0, 2.5);
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) * 0.5;
    self.backgroundColor = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:1.0 alpha:0.14]
        : [UIColor colorWithWhite:0.0 alpha:0.14];
}
- (void)setShowing:(BOOL)showing animated:(BOOL)animated {
    _showing = showing;
    [self.layer removeAllAnimations];
    if (showing) self.hidden = NO;
    void (^changes)(void) = ^{ self.alpha = showing ? 1.0 : 0.0; };
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (!self.showing && self.alpha == 0.0) self.hidden = YES;
    };
    if (animated) {
        [UIView animateWithDuration:showing ? 0.08 : 0.20
                              delay:showing ? 0.0 : 0.02
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}
@end

static LGCtxMenuGlowView *contextMenuGlowView(UIView *listView) {
    LGCtxMenuGlowView *glow = objc_getAssociatedObject(listView, kCtxGlowViewKey);
    if (!glow) {
        glow = [[LGCtxMenuGlowView alloc] initWithFrame:listView.bounds];
        glow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(listView, kCtxGlowViewKey, glow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *background = findDescendantMatching(listView, ^BOOL(UIView *view) {
            return [view isKindOfClass:UIVisualEffectView.class];
        });
        if (background && background.superview == listView) [listView insertSubview:glow aboveSubview:background];
        else [listView insertSubview:glow atIndex:0];
    }
    glow.frame = listView.bounds;
    glow.layer.cornerRadius = contextMenuCornerRadius();
    return glow;
}

static LGCtxMenuPillView *contextMenuPillView(UIView *cell) {
    LGCtxMenuPillView *pill = objc_getAssociatedObject(cell, kCtxCellPillKey);
    if (!pill) {
        pill = [[LGCtxMenuPillView alloc] initWithFrame:CGRectZero];
        [cell insertSubview:pill atIndex:0];
        objc_setAssociatedObject(cell, kCtxCellPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [pill updateForBounds:cell.bounds];
    return pill;
}

static void restoreContextMenuSubtree(UIView *view) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(view, kCtxGlassKey);
    [glass removeFromSuperview];
    objc_setAssociatedObject(view, kCtxGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
    NSNumber *alpha = objc_getAssociatedObject(view, kCtxOriginalAlphaKey);
    if (alpha) {
        view.alpha = alpha.doubleValue;
        view.hidden = [objc_getAssociatedObject(view, kCtxOriginalHiddenKey) boolValue];
        view.layer.cornerRadius = [objc_getAssociatedObject(view, kCtxOriginalRadiusKey) doubleValue];
        NSString *curve = objc_getAssociatedObject(view, kCtxOriginalCurveKey);
        view.layer.cornerCurve = curve.length ? curve : kCACornerCurveCircular;
        view.layer.masksToBounds = [objc_getAssociatedObject(view, kCtxOriginalMasksKey) boolValue];
        objc_setAssociatedObject(view, kCtxOriginalAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(view, kCtxOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(view, kCtxOriginalRadiusKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(view, kCtxOriginalCurveKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    NSValue *frame = objc_getAssociatedObject(view, kCtxOriginalFrameKey);
    if (frame) { view.frame = frame.CGRectValue; objc_setAssociatedObject(view, kCtxOriginalFrameKey, nil, OBJC_ASSOCIATION_ASSIGN); }
    NSNumber *contentMode = objc_getAssociatedObject(view, kCtxOriginalContentModeKey);
    if (contentMode) { view.contentMode = contentMode.integerValue; objc_setAssociatedObject(view, kCtxOriginalContentModeKey, nil, OBJC_ASSOCIATION_ASSIGN); }
    UIColor *background = objc_getAssociatedObject(view, kCtxGapOriginalBgKey);
    if (background) { view.backgroundColor = background; objc_setAssociatedObject(view, kCtxGapOriginalBgKey, nil, OBJC_ASSOCIATION_ASSIGN); }
    UIView *divider = [view viewWithTag:kCtxDividerTag];
    [divider removeFromSuperview];
    [objc_getAssociatedObject(view, kCtxGlowViewKey) removeFromSuperview];
    objc_setAssociatedObject(view, kCtxGlowViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    [objc_getAssociatedObject(view, kCtxCellPillKey) removeFromSuperview];
    objc_setAssociatedObject(view, kCtxCellPillKey, nil, OBJC_ASSOCIATION_ASSIGN);
    for (UIView *sub in [view.subviews copy]) restoreContextMenuSubtree(sub);
}

static void restoreContextMenusForDisable(void) {
    if (lgHostEnabled(@"ContextMenu")) return;
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        restoreContextMenuSubtree(window);
}

static void ctxRoundSubtree(UIView *v) {
    if (shouldRoundContextMenuSubview(v)) applyContextMenuRoundedStyle(v);
    for (UIView *c in v.subviews) ctxRoundSubtree(c);
}

static void ctxHideBackdropsInSubtree(UIView *v) {
    if ([v isKindOfClass:[UIVisualEffectView class]]) setBackdropHiddenInEffectView(v);
    for (UIView *c in v.subviews) ctxHideBackdropsInSubtree(c);
}

static void styleContextMenuListSubviews(UIView *listView) {
    hideContextMenuSeparators(listView);
    for (UIView *sub in listView.subviews) ctxRoundSubtree(sub);
}

static void ctxAppendViewTree(NSMutableString *dump, UIView *view, NSUInteger depth, NSUInteger *count) {
    if (!view || depth > 10 || *count >= 200) return;
    (*count)++;
    NSString *indent = [@"                    " substringToIndex:MIN(depth * 2, 20)];
    CGRect windowFrame = view.window ? [view convertRect:view.bounds toView:view.window] : CGRectNull;
    [dump appendFormat:@"%@%@ %p frame=%@ bounds=%@ window=%@ clips=%d alpha=%.2f hidden=%d transform=%@ radius=%.2f masks=%d mask=%@ safe=%@ margins=%@ constraints=%@\n",
        indent, NSStringFromClass(view.class), view, NSStringFromCGRect(view.frame),
        NSStringFromCGRect(view.bounds), NSStringFromCGRect(windowFrame), view.clipsToBounds,
        view.alpha, view.hidden, NSStringFromCGAffineTransform(view.transform),
        view.layer.cornerRadius, view.layer.masksToBounds,
        view.layer.mask ? NSStringFromClass(view.layer.mask.class) : @"nil",
        NSStringFromUIEdgeInsets(view.safeAreaInsets), NSStringFromUIEdgeInsets(view.layoutMargins),
        view.constraints];
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = (UIScrollView *)view;
        [dump appendFormat:@"%@  content=%@ inset=%@ adjusted=%@ offset=%@ scroll=%d\n",
            indent, NSStringFromCGSize(scroll.contentSize), NSStringFromUIEdgeInsets(scroll.contentInset),
            NSStringFromUIEdgeInsets(scroll.adjustedContentInset), NSStringFromCGPoint(scroll.contentOffset),
            scroll.scrollEnabled];
    }
    for (UIView *subview in view.subviews) ctxAppendViewTree(dump, subview, depth + 1, count);
}

static void ctxDumpHierarchy(UIView *listView) {
    if (!LGDebugLoggingEnabled() || objc_getAssociatedObject(listView, kCtxHierarchyProbeKey)) return;
    objc_setAssociatedObject(listView, kCtxHierarchyProbeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *root = listView;
    while (root.superview) root = root.superview;
    NSMutableString *dump = [NSMutableString stringWithString:@"[ContextMenu hierarchy]\n"];
    NSUInteger count = 0;
    ctxAppendViewTree(dump, root, 0, &count);
    LGLog(@"%@", dump);
}

static void ctxScheduleLayoutProbe(UIView *listView) {
    if (!LGDebugLoggingEnabled() || [objc_getAssociatedObject(listView, kCtxProbePendingKey) boolValue]) return;
    objc_setAssociatedObject(listView, kCtxProbePendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(listView, kCtxProbePendingKey, nil, OBJC_ASSOCIATION_ASSIGN);
        UICollectionView *collection = (UICollectionView *)findDescendantMatching(listView, ^BOOL(UIView *view) {
            return [view isKindOfClass:UICollectionView.class];
        });
        if (!collection.window) return;
        LGLog(@"[ContextMenu probe] list=%@ bounds=%@ clips=%d collection=%@ super=%@ superBounds=%@ content=%@ inset=%@ adjusted=%@ cells=%@",
              NSStringFromClass(listView.class), NSStringFromCGRect(listView.bounds), listView.clipsToBounds,
              NSStringFromCGRect(collection.frame), NSStringFromClass(collection.superview.class),
              NSStringFromCGRect(collection.superview.bounds), NSStringFromCGSize(collection.contentSize),
              NSStringFromUIEdgeInsets(collection.contentInset),
              NSStringFromUIEdgeInsets(collection.adjustedContentInset), collection.visibleCells);
    });
}

static void ctxLogOpenSnapshot(UIView *listView, NSString *phase) {
    UICollectionView *collection = (UICollectionView *)findDescendantMatching(listView, ^BOOL(UIView *view) {
        return [view isKindOfClass:UICollectionView.class];
    });
    if (!collection.window) return;
    NSArray<UICollectionViewCell *> *cells = collection.visibleCells;
    CGRect cellUnion = CGRectNull;
    for (UICollectionViewCell *cell in cells)
        cellUnion = CGRectIsNull(cellUnion) ? cell.frame : CGRectUnion(cellUnion, cell.frame);
    LGLog(@"[ContextMenu open %@] list=%p frame=%@ bounds=%@ safe=%@ margins=%@ glassCount=%lu collection=%p frame=%@ bounds=%@ content=%@ layoutContent=%@ inset=%@ adjusted=%@ safe=%@ cells=%lu cellUnion=%@ super=%p %@ superFrame=%@ superBounds=%@",
          phase, listView, NSStringFromCGRect(listView.frame), NSStringFromCGRect(listView.bounds),
          NSStringFromUIEdgeInsets(listView.safeAreaInsets), NSStringFromUIEdgeInsets(listView.layoutMargins),
          (unsigned long)ctxGlassCount(listView), collection, NSStringFromCGRect(collection.frame),
          NSStringFromCGRect(collection.bounds), NSStringFromCGSize(collection.contentSize),
          NSStringFromCGSize(collection.collectionViewLayout.collectionViewContentSize),
          NSStringFromUIEdgeInsets(collection.contentInset),
          NSStringFromUIEdgeInsets(collection.adjustedContentInset),
          NSStringFromUIEdgeInsets(collection.safeAreaInsets), (unsigned long)cells.count,
          NSStringFromCGRect(cellUnion), collection.superview, NSStringFromClass(collection.superview.class),
          NSStringFromCGRect(collection.superview.frame), NSStringFromCGRect(collection.superview.bounds));
}

static void ctxProbeMenuOpen(UIView *listView) {
    if (!LGDebugLoggingEnabled() || objc_getAssociatedObject(listView, kCtxOpenProbeKey)) return;
    objc_setAssociatedObject(listView, kCtxOpenProbeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LGLog(@"[ContextMenu open] list=%p window=%p frame=%@", listView, listView.window,
          NSStringFromCGRect(listView.frame));
    ctxLogOpenSnapshot(listView, @"now");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ctxLogOpenSnapshot(listView, @"100ms");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ctxLogOpenSnapshot(listView, @"300ms");
        ctxDumpHierarchy(listView);
    });
}

#pragma mark - hooks

%group LGContextMenuHooks

%hook UIVisualEffectView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!self_.window) return;
    if (!isInsideContextMenu(self_)) return;
    if (!lgHostEnabled(@"ContextMenu")) { restoreContextMenuSubtree(self_); return; }
    setBackdropHiddenInEffectView(self_);
    if (!hasAncestorOfClassName(self_, @"_UIContextMenuListView")) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self_.window) injectGlassIntoContextEffectView((UIVisualEffectView *)self_, 0);
    });
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!isInsideContextMenu(self_)) return;
    if (!lgHostEnabled(@"ContextMenu")) { restoreContextMenuSubtree(self_); return; }
    setBackdropHiddenInEffectView(self_);
    if (hasAncestorOfClassName(self_, @"_UIContextMenuListView"))
        injectGlassIntoContextEffectView((UIVisualEffectView *)self_, 10);
}
%end

%hook UICollectionReusableView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!isContextMenuReusableGapView(self_)) return;
    if (!hasAncestorOfClassName(self_, @"_UIContextMenuListView")) return;
    if (!lgHostEnabled(@"ContextMenu")) { restoreContextMenuSubtree(self_); return; }
    styleContextMenuReusableGapView(self_);
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!isContextMenuReusableGapView(self_)) return;
    if (!hasAncestorOfClassName(self_, @"_UIContextMenuListView")) return;
    if (lgHostEnabled(@"ContextMenu")) styleContextMenuReusableGapView(self_);
    else restoreContextMenuSubtree(self_);
}
%end

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    if (hasAncestorOfClassName((UIView *)self, @"_UIContextMenuListView") && lgHostEnabled(@"ContextMenu"))
        hideContextMenuSeparators((UIView *)self);
}
%end

%hook _UIContextMenuContainerView
- (void)layoutSubviews {
    %orig;
    if (lgHostEnabled(@"ContextMenu")) ctxHideBackdropsInSubtree((UIView *)self);
    else restoreContextMenuSubtree((UIView *)self);
}
%end

%hook _UIContextMenuListView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!self_.window) {
        removeGlassFromContextListView(self_);
        return;
    }
    if (lgHostEnabled(@"ContextMenu")) ctxProbeMenuOpen(self_);
}
- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (!lgHostEnabled(@"ContextMenu")) { restoreContextMenuSubtree((UIView *)self); return; }
    if (![subview isKindOfClass:[UIVisualEffectView class]] && shouldRoundContextMenuSubview(subview))
        applyContextMenuRoundedStyle(subview);
    if (lgHostEnabled(@"ContextMenu")) styleContextMenuListSubviews((UIView *)self);
    else restoreContextMenuSubtree((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    if (lgHostEnabled(@"ContextMenu")) {
        styleContextMenuListSubviews((UIView *)self);
        contextMenuGlowView((UIView *)self);
        ctxScheduleLayoutProbe((UIView *)self);
        ctxDumpHierarchy((UIView *)self);
    } else restoreContextMenuSubtree((UIView *)self);
}
- (void)highlightItemAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    if (!lgHostEnabled(@"ContextMenu") || !indexPath) return;
    UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
    [contextMenuPillView(cell) setShowing:YES animated:YES];
}
- (void)unHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    if (!lgHostEnabled(@"ContextMenu") || !indexPath) return;
    UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
    LGCtxMenuPillView *pill = objc_getAssociatedObject(cell, kCtxCellPillKey);
    [pill setShowing:NO animated:YES];
}
%end

%hook _UIContextMenuView
- (void)_handleSelectionGesture:(UIGestureRecognizer *)gesture {
    %orig;
    if (!lgHostEnabled(@"ContextMenu") || !gesture) return;
    UIView *listView = self.currentListView;
    if (!listView.window) return;
    LGCtxMenuGlowView *glow = contextMenuGlowView(listView);
    if (gesture.state == UIGestureRecognizerStateBegan && gesture.numberOfTouches > 0) {
        [glow showAtPoint:[gesture locationInView:listView]];
    } else if (gesture.state == UIGestureRecognizerStateChanged && gesture.numberOfTouches > 0) {
        [glow moveToPoint:[gesture locationInView:listView]];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        [glow hideGlow];
    }
}
%end

%hook _UIContextMenuCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:
    (UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *fitted = %orig;
    if (lgHostEnabled(@"ContextMenu")) {
        CGSize size = fitted.size;
        size.height = kCtxRowHeight;
        fitted.size = size;
    }
    return fitted;
}
- (void)layoutSubviews {
    %orig;
    if (lgHostEnabled(@"ContextMenu"))
        [objc_getAssociatedObject(self, kCtxCellPillKey) updateForBounds:((UIView *)self).bounds];
}
- (void)setHighlighted:(BOOL)highlighted {
    %orig(lgHostEnabled(@"ContextMenu") ? NO : highlighted);
    if (lgHostEnabled(@"ContextMenu"))
        [contextMenuPillView((UIView *)self) setShowing:highlighted animated:YES];
}
- (void)setSelected:(BOOL)selected {
    %orig(lgHostEnabled(@"ContextMenu") ? NO : selected);
    if (lgHostEnabled(@"ContextMenu") && selected)
        [contextMenuPillView((UIView *)self) setShowing:YES animated:NO];
}
%end

%hook _UIContextMenuCellContentView
- (void)layoutSubviews {
    %orig;
    if (lgHostEnabled(@"ContextMenu")) relayoutContextMenuCellContent((UIView *)self);
    else restoreContextMenuSubtree((UIView *)self);
}
%end

%end

%ctor {
    if (LGIsExcludedSystemProcess()) return;
    %init(LGContextMenuHooks);
    lgObservePreferenceReload(^{ restoreContextMenusForDisable(); });
}
