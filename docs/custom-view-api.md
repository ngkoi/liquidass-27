# custom view api

include `<LiquidAss/LGCustomViewAPI.h>` in a tweak src file and call `LGCVRegister`. no link dependency is needed. your tweak must be injected into the target process.

```objc
NSError *error = nil;
LGCVRegister(@"com_example_widget_card", @{
    @"Name": @"Example card",
    @"TargetClass": @"ExampleCardView",
    @"ParentClass": @"ExampleContainerView",
    @"BezelWidth": @18.0,
    @"GlassThickness": @110.0,
    @"RefractionScale": @1.8,
    @"SpecularMode": @"glass",
    @"ClearBackground": @YES
}, YES, NO, &error);
```

identifiers are unique across tweaks and limited to letters, numbers, `_`, and `-`; prefix them with a vendor or tweak name. to use Custom Views defaults, pass `nil` for `configuration`. configuration values are defaults: if the user edited the values manually inside the rule created from your tweak (inside liquidass' More Options -> Custom Views), that value gets preferred, and re-registering updates untouched defaults. `nonRemovable` hides Delete Rule in prefs and blocks api removal. `hiddenFromPrefs` hides the rule from Custom Views, use `NO` to leave it visible and configurable.

remove an api-registered rule with `LGCVRemove` and will return `NO` if the rule was not registered through the API or if it was registered as nonremovable.

```objc
NSError *error = nil;
if (!LGCVRemove(@"com_example_widget_card", &error)) {
    NSLog(@"could not remove custom view rule: %@", error);
}
```

configuration keys are `Name`, `Enabled`, `TargetClass`, `ParentClass`, `GrandparentClass`, `AncestorClass`, `ChildClass`, `GrandchildClass`, `DescendantClass`, `SiblingClass`, `ClearBackground`, `BezelWidth`, `GlassThickness`, `RefractionScale`, `RefractiveIndex`, `DispersionEnabled`, `DispersionStrength`, `SpecularMode`, `SpecularOpacity`, `Blur`, `CustomScaleEnabled`, `CustomScale`, `LightTintColor`, and `DarkTintColor`. Class fields accept comma or newline-separated exact class names. tint values use `#RRGGBBAA` and unspecified values use the Custom Views defaults, custom scale is adaptive unless `CustomScaleEnabled` is true.
