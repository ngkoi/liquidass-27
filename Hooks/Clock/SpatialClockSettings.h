#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

#define kSpatialClockSettingsUpdatedNotification "com.ngkhoi.26lock.clocksettingsupdated"

@interface SpatialClockSettings : NSObject
// those things are for my app, no need to touch them
@property (nonatomic, assign) CGFloat blurRadius;

@property (nonatomic, assign) CGFloat bezelWidth;

@property (nonatomic, assign) CGFloat refractionAmount;

@property (nonatomic, assign) CGFloat refractionIndex;

+ (instancetype)sharedSettings;

- (void)loadSettings;
- (void)saveSettings;
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
