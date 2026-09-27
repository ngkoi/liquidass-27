#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const kLGPrefsUIRefreshNotification;
FOUNDATION_EXPORT NSString * const kLGPrefsRespringChangedNotification;
FOUNDATION_EXPORT NSString * const kLGLastSurfaceKey;
FOUNDATION_EXPORT NSString * const kLGPrefsLanguageChangedNotification;
FOUNDATION_EXPORT NSString * const kLGPrefsLanguageKey;

Class LGPrefsSwitchClass(void);
Class LGPrefsSliderClass(void);

NSString *LGLocalized(NSString *key);
NSString *LGPrefsAppName(void);
NSString *LGFormatSliderValue(CGFloat value, NSInteger decimals);
NSString *LGCurrentPrefsLanguageCode(void);
void LGSetCurrentPrefsLanguageCode(NSString *languageCode);

NSUserDefaults *LGPrefsUIStateDefaults(void);
void LGSynchronizeSurfaceStateDefaults(void);
NSString *LGLastSurfaceIdentifier(void);
void LGSetLastSurfaceIdentifier(NSString *identifier);
void LGClearLastSurfaceIdentifierIfMatching(NSString *identifier);
void LGObservePrefsNotifications(id target);

BOOL LGNeedsRespring(void);
BOOL LGRespringBarDismissed(void);
void LGSetRespringBarDismissed(BOOL dismissed);
void LGSetNeedsRespring(BOOL needsRespring);
void LGForceSynchronizePreferences(void);

NSNumber *LGReadPreference(NSString *key, NSNumber *fallback);
void LGWritePreference(NSString *key, NSNumber *value);
void LGWritePreferenceAndMaybeRequireRespring(NSString *key, NSNumber *value);
id LGReadPreferenceObject(NSString *key, id fallback);
void LGWritePreferenceObject(NSString *key, id value);
void LGRemovePreference(NSString *key);

NSDictionary *LGSwitchSetting(NSString *key, NSString *title, NSString *subtitle, BOOL fallback);
NSDictionary *LGSectionSetting(NSString *title, NSString *subtitle);
NSDictionary *LGNavSetting(NSString *title, NSString *subtitle, NSString *action);
NSDictionary *LGMenuSetting(NSString *key, NSString *title, NSString *subtitle, NSString *fallback, NSArray<NSDictionary *> *choices);
NSDictionary *LGSliderSetting(NSString *key, NSString *title, NSString *subtitle,
                              CGFloat fallback, CGFloat min, CGFloat max, NSInteger decimals);
NSDictionary *LGGlassQualitySetting(NSString *key, CGFloat fallback, CGFloat min, CGFloat max, NSInteger decimals);
NSDictionary *LGScaleBudgetSetting(void);
NSDictionary *LGGlassEnabledSetting(NSString *key, BOOL fallback);
BOOL LGPrefsItemIsVisible(NSDictionary *item);

NSArray<NSDictionary *> *LGDockItems(void);
NSArray<NSDictionary *> *LGRendererItemsForHostPrefix(NSString *prefix);
NSArray<NSDictionary *> *LGFolderItems(void);
NSArray<NSDictionary *> *LGAppIconItems(void);
NSArray<NSDictionary *> *LGSearchPillItems(void);
NSArray<NSDictionary *> *LGContextMenuItems(void);
NSArray<NSDictionary *> *LGControlCenterItems(void);
NSArray<NSDictionary *> *LGClockItems(void);
NSArray<NSDictionary *> *LGTabBarItems(void);
NSArray<NSDictionary *> *LGGlobalControlsItems(void);
NSArray<NSDictionary *> *LGLockscreenItems(void);
NSArray<NSDictionary *> *LGAppLibraryItems(void);
NSArray<NSDictionary *> *LGWidgetItems(void);
NSArray<NSDictionary *> *LGKeyboardItems(void);
NSArray<NSDictionary *> *LGHomescreenItems(void);
NSArray<NSDictionary *> *LGAllSurfaceItems(void);
NSArray<NSDictionary *> *LGPrefsSettingsItems(void);
NSArray<NSDictionary *> *LGMoreOptionsItems(void);
NSArray<NSDictionary *> *LGCustomViewsItems(void);
NSArray<NSString *> *LGCustomViewRuleIDs(void);
NSString *LGCreateCustomViewRule(void);
void LGDeleteCustomViewRule(NSString *ruleID);
NSArray<NSDictionary *> *LGCustomViewRuleItems(NSString *ruleID);
NSArray<NSString *> *LGAllCustomViewPreferenceKeys(void);

NSString *LGExportPreferencesJSONString(void);
BOOL LGImportPreferencesJSONString(NSString *jsonString, NSError **error);

void LGResetAllPreferences(void);
void LGResetPreferencesForKeys(NSArray<NSString *> *keys);
