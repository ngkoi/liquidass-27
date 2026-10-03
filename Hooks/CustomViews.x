#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGSharedSupport.h"
#import "../Shared/LGHostRegistry.h"
#import <objc/runtime.h>
#import <math.h>
#import <notify.h>

static void *kLGCustomGlassKey = &kLGCustomGlassKey;
static void *kLGCustomRuleIDKey = &kLGCustomRuleIDKey;
static void *kLGCustomBackgroundKey = &kLGCustomBackgroundKey;
static void *kLGCustomLayerBackgroundKey = &kLGCustomLayerBackgroundKey;
static void *kLGCustomHiddenKey = &kLGCustomHiddenKey;
static NSArray<NSDictionary *> *sLGCustomRules;
static NSSet<NSString *> *sLGCustomTargetClasses;
static BOOL sLGCustomEnabled;
static NSObject *sLGCustomAPILock;

static NSObject *LGCustomAPILock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sLGCustomAPILock = [NSObject new]; });
    return sLGCustomAPILock;
}

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
    glass.lgSpecularEnabledOverride = nil;
    glass.lgSpecularOpacityOverride = @(LG_prefFloat(LGCustomRuleKey(rule, @"SpecularOpacity"),
                                                     kLGHostRegistry[LGHostIdentifierCustomViews].specularOpacity));
    glass.lgNativeBlurRadiusOverride = @(LG_prefFloat(LGCustomRuleKey(rule, @"Blur"),
                                                      kLGHostRegistry[LGHostIdentifierCustomViews].blur));
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

static NSError *LGCustomAPIError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"dylv.liquidass.custom-view-api"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL LGCustomAPIValidIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0 || identifier.length > 96)
        return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    for (NSUInteger index = 0; index < identifier.length; index++)
        if (![allowed characterIsMember:[identifier characterAtIndex:index]]) return NO;
    return YES;
}

static BOOL LGCustomAPIValidTint(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 9 ||
        ![value hasPrefix:@"#"]) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:
        @"0123456789abcdefABCDEF"];
    for (NSUInteger index = 1; index < 9; index++)
        if (![hex characterIsMember:[value characterAtIndex:index]]) return NO;
    return YES;
}

static BOOL LGCustomAPIValidateConfiguration(NSDictionary *configuration, NSError **error) {
    if (configuration && ![configuration isKindOfClass:NSDictionary.class]) {
        if (error) *error = LGCustomAPIError(2, @"Configuration must be a dictionary");
        return NO;
    }
    NSSet *strings = [NSSet setWithArray:@[
        @"Name", @"TargetClass", @"ParentClass", @"GrandparentClass", @"AncestorClass",
        @"ChildClass", @"GrandchildClass", @"DescendantClass", @"SiblingClass"
    ]];
    NSSet *numbers = [NSSet setWithArray:@[
        @"BezelWidth", @"GlassThickness", @"RefractionScale", @"RefractiveIndex",
        @"DispersionStrength", @"SpecularOpacity", @"Blur", @"CustomScale"
    ]];
    NSSet *booleans = [NSSet setWithArray:@[
        @"Enabled", @"ClearBackground", @"DispersionEnabled", @"CustomScaleEnabled"
    ]];
    NSSet *allowed = [NSSet setWithArray:@[
        @"Name", @"TargetClass", @"ParentClass", @"GrandparentClass", @"AncestorClass",
        @"ChildClass", @"GrandchildClass", @"DescendantClass", @"SiblingClass",
        @"Enabled", @"ClearBackground", @"BezelWidth", @"GlassThickness", @"RefractionScale",
        @"RefractiveIndex", @"DispersionEnabled", @"DispersionStrength", @"SpecularMode",
        @"SpecularOpacity", @"Blur", @"CustomScaleEnabled", @"CustomScale",
        @"LightTintColor", @"DarkTintColor"
    ]];
    for (id key in configuration) {
        id value = configuration[key];
        if (![key isKindOfClass:NSString.class] || ![allowed containsObject:key]) {
            if (error) *error = LGCustomAPIError(3, [NSString stringWithFormat:@"Unsupported rule field: %@", key]);
            return NO;
        }
        if ([strings containsObject:key] && ![value isKindOfClass:NSString.class]) {
            if (error) *error = LGCustomAPIError(4, [NSString stringWithFormat:@"%@ must be a string", key]);
            return NO;
        }
        if ([booleans containsObject:key] && ![value isKindOfClass:NSNumber.class]) {
            if (error) *error = LGCustomAPIError(5, [NSString stringWithFormat:@"%@ must be a number", key]);
            return NO;
        }
        if ([numbers containsObject:key] && ![value isKindOfClass:NSNumber.class]) {
            if (error) *error = LGCustomAPIError(6, [NSString stringWithFormat:@"%@ must be numeric", key]);
            return NO;
        }
        if (([key isEqualToString:@"LightTintColor"] || [key isEqualToString:@"DarkTintColor"]) &&
            !LGCustomAPIValidTint(value)) {
            if (error) *error = LGCustomAPIError(7, [NSString stringWithFormat:@"%@ must be #RRGGBBAA", key]);
            return NO;
        }
        if ([key isEqualToString:@"SpecularMode"] &&
            ![@[@"none", @"border", @"glass"] containsObject:value]) {
            if (error) *error = LGCustomAPIError(8, @"SpecularMode must be none, border, or glass");
            return NO;
        }
    }
    NSDictionary<NSString *, NSArray<NSNumber *> *> *ranges = @{
        @"BezelWidth": @[@0.0, @80.0], @"GlassThickness": @[@0.0, @220.0],
        @"RefractionScale": @[@0.0, @5.0], @"RefractiveIndex": @[@1.0, @3.0],
        @"DispersionStrength": @[@0.0, @10.0], @"SpecularOpacity": @[@0.0, @1.0],
        @"Blur": @[@0.0, @50.0], @"CustomScale": @[@0.1, @1.5]
    };
    for (NSString *key in numbers) {
        NSNumber *number = configuration[key];
        if (!number) continue;
        double value = number.doubleValue;
        NSArray<NSNumber *> *range = ranges[key];
        if (!isfinite(value) || value < range[0].doubleValue || value > range[1].doubleValue) {
            if (error) *error = LGCustomAPIError(10, [NSString stringWithFormat:@"%@ is out of range", key]);
            return NO;
        }
    }
    return YES;
}

__attribute__((visibility("default")))
BOOL LGCVRegister(NSString *identifier, NSDictionary *configuration,
                  BOOL nonRemovable, BOOL hiddenFromPrefs, NSError **error) {
    if (error) *error = nil;
    if (!LGCustomAPIValidIdentifier(identifier)) {
        if (error) *error = LGCustomAPIError(1, @"Identifier must use 1-96 letters, numbers, underscores, or hyphens");
        return NO;
    }
    if (!LGCustomAPIValidateConfiguration(configuration, error)) return NO;

    NSString *base = [@"CustomViews.Rule." stringByAppendingString:identifier];
    NSString *managedKey = [base stringByAppendingString:@".APIManaged"];
    NSString *existingKey = [base stringByAppendingString:@".TargetClass"];
    @synchronized (LGCustomAPILock()) {
        id managed = CFBridgingRelease(CFPreferencesCopyAppValue(
            (__bridge CFStringRef)managedKey, (__bridge CFStringRef)LGPrefsDomain));
        id existing = CFBridgingRelease(CFPreferencesCopyAppValue(
            (__bridge CFStringRef)existingKey, (__bridge CFStringRef)LGPrefsDomain));
        if (existing && ![managed boolValue]) {
            if (error) *error = LGCustomAPIError(11, @"Identifier is already used by a user-created rule");
            return NO;
        }

        NSMutableDictionary *values = [@{
            @"Name": identifier, @"Enabled": @YES, @"TargetClass": @"",
            @"ParentClass": @"", @"GrandparentClass": @"", @"AncestorClass": @"",
            @"ChildClass": @"", @"GrandchildClass": @"", @"DescendantClass": @"",
            @"SiblingClass": @"", @"ClearBackground": @YES,
            @"BezelWidth": @16.0, @"GlassThickness": @100.0, @"RefractionScale": @1.5,
            @"RefractiveIndex": @1.5, @"DispersionEnabled": @YES, @"DispersionStrength": @2.0,
            @"SpecularMode": @"glass", @"SpecularOpacity": @0.5, @"Blur": @8.0,
            @"CustomScaleEnabled": @NO, @"CustomScale": @1.0,
            @"LightTintColor": @"#00000000", @"DarkTintColor": @"#00000000"
        } mutableCopy];
        [values addEntriesFromDictionary:configuration ?: @{}];
        NSString *defaultsKey = [base stringByAppendingString:@".APIDefaults"];
        id oldDefaults = CFBridgingRelease(CFPreferencesCopyAppValue(
            (__bridge CFStringRef)defaultsKey, (__bridge CFStringRef)LGPrefsDomain));
        id storedOverrides = CFBridgingRelease(CFPreferencesCopyAppValue(
            (__bridge CFStringRef)[base stringByAppendingString:@".APIUserOverrides"],
            (__bridge CFStringRef)LGPrefsDomain));
        NSSet *userOverrides = [storedOverrides isKindOfClass:NSArray.class]
            ? [NSSet setWithArray:storedOverrides] : [NSSet set];
        NSMutableDictionary *updates = [NSMutableDictionary dictionaryWithCapacity:values.count + 2];
        [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, __unused BOOL *stop) {
            NSString *preferenceKey = [base stringByAppendingFormat:@".%@", key];
            id existingValue = CFBridgingRelease(CFPreferencesCopyAppValue(
                (__bridge CFStringRef)preferenceKey, (__bridge CFStringRef)LGPrefsDomain));
            id previousDefault = [oldDefaults isKindOfClass:NSDictionary.class] ? oldDefaults[key] : nil;
            if (![userOverrides containsObject:key] &&
                (!existingValue || (previousDefault && [existingValue isEqual:previousDefault])))
                updates[preferenceKey] = value;
        }];
        updates[defaultsKey] = values;
        updates[managedKey] = @YES;
        updates[[base stringByAppendingString:@".APINonRemovable"]] = @(nonRemovable);
        updates[[base stringByAppendingString:@".APIHiddenFromPrefs"]] = @(hiddenFromPrefs);

        NSMutableArray<NSString *> *ruleIDs = [LGCustomRuleIDs() mutableCopy];
        if (![ruleIDs containsObject:identifier]) [ruleIDs addObject:identifier];
        updates[@"CustomViews.RuleIDs"] = ruleIDs;
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)updates, NULL,
                                 (__bridge CFStringRef)LGPrefsDomain,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize((__bridge CFStringRef)LGPrefsDomain);
    }

    LGReloadPreferences();
    LGInvalidateGlassPreferenceCache();
    LGCustomReload();
    notify_post(LGPrefsChangedNotificationCString);
    return YES;
}

__attribute__((visibility("default")))
BOOL LGCVRemove(NSString *identifier, NSError **error) {
    if (error) *error = nil;
    if (!LGCustomAPIValidIdentifier(identifier)) {
        if (error) *error = LGCustomAPIError(1, @"Invalid rule identifier");
        return NO;
    }
    NSString *base = [@"CustomViews.Rule." stringByAppendingString:identifier];
    NSString *managedKey = [base stringByAppendingString:@".APIManaged"];
    NSString *nonRemovableKey = [base stringByAppendingString:@".APINonRemovable"];
    @synchronized (LGCustomAPILock()) {
        id managed = CFBridgingRelease(CFPreferencesCopyAppValue(
            (__bridge CFStringRef)managedKey, (__bridge CFStringRef)LGPrefsDomain));
        if (![managed boolValue]) {
            if (error) *error = LGCustomAPIError(12, @"Rule is not registered through the API");
            return NO;
        }
        id protected = CFBridgingRelease(CFPreferencesCopyAppValue(
            (__bridge CFStringRef)nonRemovableKey, (__bridge CFStringRef)LGPrefsDomain));
        if ([protected boolValue]) {
            if (error) *error = LGCustomAPIError(13, @"Rule is non-removable");
            return NO;
        }

        NSMutableArray<NSString *> *ruleIDs = [LGCustomRuleIDs() mutableCopy];
        [ruleIDs removeObject:identifier];
        NSArray *suffixes = @[
            @"Name", @"Enabled", @"TargetClass", @"ParentClass", @"GrandparentClass",
            @"AncestorClass", @"ChildClass", @"GrandchildClass", @"DescendantClass",
            @"SiblingClass", @"ClearBackground", @"BezelWidth", @"GlassThickness",
            @"RefractionScale", @"RefractiveIndex", @"DispersionEnabled", @"DispersionStrength",
            @"SpecularMode", @"SpecularOpacity", @"Blur", @"CustomScaleEnabled", @"CustomScale",
            @"LightTintColor", @"DarkTintColor", @"APIManaged", @"APINonRemovable",
            @"APIHiddenFromPrefs", @"APIDefaults", @"APIUserOverrides"
        ];
        NSMutableArray<NSString *> *remove = [NSMutableArray arrayWithCapacity:suffixes.count + 1];
        for (NSString *suffix in suffixes)
            [remove addObject:[base stringByAppendingFormat:@".%@", suffix]];
        NSDictionary *updates = @{ @"CustomViews.RuleIDs": ruleIDs };
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)updates,
                                 (__bridge CFArrayRef)remove,
                                 (__bridge CFStringRef)LGPrefsDomain,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize((__bridge CFStringRef)LGPrefsDomain);
    }

    LGReloadPreferences();
    LGInvalidateGlassPreferenceCache();
    LGCustomReload();
    notify_post(LGPrefsChangedNotificationCString);
    return YES;
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
