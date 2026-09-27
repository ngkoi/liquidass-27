#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGSharedSupport.h"
#import "../Shared/LGHostRegistry.h"
#import <objc/runtime.h>

static void *kLGCustomGlassKey = &kLGCustomGlassKey;
static void *kLGCustomRuleIDKey = &kLGCustomRuleIDKey;
static void *kLGCustomBackgroundKey = &kLGCustomBackgroundKey;
static void *kLGCustomLayerBackgroundKey = &kLGCustomLayerBackgroundKey;
static void *kLGCustomHiddenKey = &kLGCustomHiddenKey;
static NSArray<NSDictionary *> *sLGCustomRules;
static NSSet<NSString *> *sLGCustomTargetClasses;
static BOOL sLGCustomEnabled;

static NSString *LGCustomRuleKey(NSDictionary *rule, NSString *suffix) {
    return [NSString stringWithFormat:@"CustomViews.Rule.%@.%@", rule[@"ID"], suffix];
}

static NSArray<NSString *> *LGCustomClassNames(NSString *value) {
    if (!value.length) return @[];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",\n"];
    for (NSString *part in [value componentsSeparatedByCharactersInSet:separators]) {
        NSString *name = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length) [names addObject:name];
    }
    return names;
}

static BOOL LGCustomMatchesClass(id object, NSString *value) {
    if (!value.length) return YES;
    return object && [LGCustomClassNames(value) containsObject:NSStringFromClass([object class])];
}

static UIViewController *LGCustomOwningController(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder)
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    return nil;
}

static BOOL LGCustomHasDescendant(UIView *view, NSString *value, NSUInteger depth) {
    if (!value.length) return YES;
    for (UIView *child in view.subviews) {
        if (LGCustomMatchesClass(child, value)) return YES;
        if (depth > 1 && LGCustomHasDescendant(child, value, depth - 1)) return YES;
    }
    return NO;
}

static BOOL LGCustomMatchesRule(UIView *view, NSDictionary *rule) {
    if (!LGCustomMatchesClass(view, rule[@"TargetClass"])) return NO;
    UIViewController *controller = LGCustomOwningController(view);
    NSString *parentName = rule[@"ParentClass"];
    if (parentName.length && !LGCustomMatchesClass(view.superview, parentName) &&
        !LGCustomMatchesClass(controller, parentName)) return NO;
    NSString *grandparentName = rule[@"GrandparentClass"];
    if (grandparentName.length && !LGCustomMatchesClass(view.superview.superview, grandparentName) &&
        !LGCustomMatchesClass(controller.parentViewController, grandparentName)) return NO;
    NSString *ancestorName = rule[@"AncestorClass"];
    if (ancestorName.length) {
        BOOL found = NO;
        for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
            if (LGCustomMatchesClass(ancestor, ancestorName)) { found = YES; break; }
        }
        for (UIViewController *ancestor = controller; !found && ancestor;
             ancestor = ancestor.parentViewController)
            if (LGCustomMatchesClass(ancestor, ancestorName)) found = YES;
        if (!found) return NO;
    }
    if (!LGCustomHasDescendant(view, rule[@"ChildClass"], 1)) return NO;
    if (!LGCustomHasDescendant(view, rule[@"GrandchildClass"], 2)) return NO;
    if (!LGCustomHasDescendant(view, rule[@"DescendantClass"], NSUIntegerMax)) return NO;
    NSString *siblingName = rule[@"SiblingClass"];
    if (siblingName.length) {
        BOOL found = NO;
        for (UIView *sibling in view.superview.subviews) {
            if (sibling != view && LGCustomMatchesClass(sibling, siblingName)) { found = YES; break; }
        }
        if (!found) return NO;
    }
    return YES;
}

static NSDictionary *LGCustomMatchingRule(UIView *view) {
    if (!sLGCustomEnabled || ![sLGCustomTargetClasses containsObject:NSStringFromClass(view.class)]) return nil;
    for (NSDictionary *rule in sLGCustomRules)
        if (LGCustomMatchesRule(view, rule)) return rule;
    return nil;
}

static NSString *LGCustomFilterType(NSString *ruleID) {
    NSMutableString *safeID = [NSMutableString stringWithCapacity:ruleID.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    for (NSUInteger index = 0; index < ruleID.length; index++) {
        unichar character = [ruleID characterAtIndex:index];
        unichar safeCharacter = [allowed characterIsMember:character] ? character : (unichar)'_';
        [safeID appendFormat:@"%C", safeCharacter];
    }
    return [@"dylv.liquidglass.custom." stringByAppendingString:safeID];
}

static void LGCustomRestoreBackground(UIView *view) {
    id background = objc_getAssociatedObject(view, kLGCustomBackgroundKey);
    id layerBackground = objc_getAssociatedObject(view, kLGCustomLayerBackgroundKey);
    if (background) view.backgroundColor = background == NSNull.null ? nil : background;
    if (layerBackground)
        view.layer.backgroundColor = layerBackground == NSNull.null
            ? nil : (__bridge CGColorRef)layerBackground;
}

static void LGCustomRestoreVisibility(UIView *view) {
    NSNumber *hidden = objc_getAssociatedObject(view, kLGCustomHiddenKey);
    if (hidden) view.hidden = hidden.boolValue;
}

static void LGCustomRemove(UIView *view) {
    [objc_getAssociatedObject(view, kLGCustomGlassKey) removeFromSuperview];
    objc_setAssociatedObject(view, kLGCustomGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, kLGCustomRuleIDKey, nil, OBJC_ASSOCIATION_ASSIGN);
    LGCustomRestoreBackground(view);
    LGCustomRestoreVisibility(view);
}

static void LGCustomApply(UIView *view) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(view, kLGCustomGlassKey);
    NSDictionary *rule = view.window && !CGRectIsEmpty(view.bounds)
        ? LGCustomMatchingRule(view) : nil;
    if (!rule) {
        if (glass) LGCustomRemove(view);
        return;
    }
    NSString *ruleID = rule[@"ID"];
    if (glass && ![objc_getAssociatedObject(view, kLGCustomRuleIDKey) isEqualToString:ruleID]) {
        LGCustomRemove(view);
        glass = nil;
    }
    if (!objc_getAssociatedObject(view, kLGCustomBackgroundKey)) {
        objc_setAssociatedObject(view, kLGCustomBackgroundKey,
                                 view.backgroundColor ?: NSNull.null,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kLGCustomLayerBackgroundKey,
                                 view.layer.backgroundColor
                                     ? (__bridge id)view.layer.backgroundColor : NSNull.null,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kLGCustomHiddenKey, @(view.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL suppressTarget = LG_prefBool(LGCustomRuleKey(rule, @"ClearBackground"), YES);
    if (suppressTarget) view.hidden = YES;
    else {
        LGCustomRestoreBackground(view);
        LGCustomRestoreVisibility(view);
    }
    if (!glass) {
        glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds groupName:nil
                                               filterType:LGCustomFilterType(ruleID)];
        glass.userInteractionEnabled = NO;
        [view.superview insertSubview:glass belowSubview:view];
        objc_setAssociatedObject(view, kLGCustomGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kLGCustomRuleIDKey, ruleID,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        LGLog(@"custom view attached rule=%@ class=%@", ruleID,
              NSStringFromClass(view.class));
    }
    if (glass.superview != view.superview)
        [view.superview insertSubview:glass belowSubview:view];
    glass.bounds = view.bounds;
    glass.center = view.center;
    glass.transform = view.transform;
    glass.layer.cornerRadius = view.layer.cornerRadius;
    glass.layer.cornerCurve = view.layer.cornerCurve;
    glass.layer.maskedCorners = view.layer.maskedCorners;
    glass.layer.masksToBounds = YES;
    glass.lgSpecularEnabledOverride = @(LG_prefBool(LGCustomRuleKey(rule, @"SpecularEnabled"), YES));
    glass.lgSpecularOpacityOverride = @(LG_prefFloat(LGCustomRuleKey(rule, @"SpecularOpacity"),
                                                     kLGHostRegistry[LGHostIdentifierCustomViews].specularOpacity));
    glass.lgNativeBlurRadiusOverride = @(LG_prefFloat(LGCustomRuleKey(rule, @"Blur"),
                                                      kLGHostRegistry[LGHostIdentifierCustomViews].blur));
    glass.lgQualityScaleOverride = @(LG_prefFloat(LGCustomRuleKey(rule, @"Quality"),
                                                  LG_CUSTOM_VIEW_DEFAULT_QUALITY));
    [glass applyFilters];
}

static NSArray<NSString *> *LGCustomRuleIDs(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("CustomViews.RuleIDs"),
                                                        (__bridge CFStringRef)LGPrefsDomain);
    id stored = CFBridgingRelease(value);
    return [stored isKindOfClass:NSArray.class] ? stored : @[];
}

static void LGCustomScanView(UIView *view) {
    if ([sLGCustomTargetClasses containsObject:NSStringFromClass(view.class)] ||
        objc_getAssociatedObject(view, kLGCustomGlassKey)) LGCustomApply(view);
    for (UIView *child in view.subviews) LGCustomScanView(child);
}

static void LGCustomReload(void) {
    NSMutableArray<NSDictionary *> *rules = [NSMutableArray array];
    NSMutableSet<NSString *> *targets = [NSMutableSet set];
    for (id value in LGCustomRuleIDs()) {
        if (![value isKindOfClass:NSString.class] || ![value length]) continue;
        NSDictionary *stub = @{ @"ID": value };
        if (!LG_prefBool(LGCustomRuleKey(stub, @"Enabled"), YES)) continue;
        NSString *target = LG_prefString(LGCustomRuleKey(stub, @"TargetClass"), @"");
        if (!target.length) continue;
        NSMutableDictionary *rule = [stub mutableCopy];
        for (NSString *suffix in @[@"TargetClass", @"ParentClass", @"GrandparentClass",
                                    @"AncestorClass", @"ChildClass", @"GrandchildClass",
                                    @"DescendantClass", @"SiblingClass"])
            rule[suffix] = LG_prefString(LGCustomRuleKey(stub, suffix), @"");
        [targets addObjectsFromArray:LGCustomClassNames(target)];
        [rules addObject:rule];
    }
    sLGCustomRules = rules;
    sLGCustomTargetClasses = targets;
    sLGCustomEnabled = LG_globalEnabled() && LG_prefBool(@"CustomViews.Enabled", NO);
    for (UIWindow *window in UIApplication.sharedApplication.windows) LGCustomScanView(window);
}

%group LGCustomViews
%hook UIView
- (void)didMoveToWindow {
    %orig;
    if ([sLGCustomTargetClasses containsObject:NSStringFromClass(self.class)] ||
        objc_getAssociatedObject(self, kLGCustomGlassKey)) LGCustomApply(self);
}
- (void)layoutSubviews {
    %orig;
    if ([sLGCustomTargetClasses containsObject:NSStringFromClass(self.class)] ||
        objc_getAssociatedObject(self, kLGCustomGlassKey)) LGCustomApply(self);
}
%end
%end

%ctor {
    if (LGIsExcludedSystemProcess()) return;
    LGCustomReload();
    LGObservePreferenceChanges(^{ LGCustomReload(); });
    %init(LGCustomViews);
}
