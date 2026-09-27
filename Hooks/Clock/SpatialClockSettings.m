#import "SpatialClockSettings.h"
#import <notify.h>

static NSString *SpatialSettingsFilePath(void) {
    NSString *rootless = @"/var/jb/var/mobile/Library/Application Support/26Lock/settings.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootless]) return rootless;
    NSString *std = @"/var/mobile/Library/Application Support/26Lock/settings.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:std]) return std;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        return rootless;
    }
    return std;
}

static NSString *LiquidAssPrefsFilePath(void) {
    NSString *rootless = @"/var/jb/var/mobile/Library/Preferences/dylv.liquidassprefs.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootless]) return rootless;
    return @"/var/mobile/Library/Preferences/dylv.liquidassprefs.plist";
}

@implementation SpatialClockSettings

+ (instancetype)sharedSettings {
    static SpatialClockSettings *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SpatialClockSettings alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self resetToDefaultsWithoutSaving];
        [self loadSettings];
    }
    return self;
}

- (void)resetToDefaultsWithoutSaving {
    _blurRadius = 9.0f;
    _bezelWidth = 12.0f;
    _refractionAmount = 2.60f;
    _refractionIndex = 1.60f;
}

- (void)resetToDefaults {
    [self resetToDefaultsWithoutSaving];
    [self saveSettings];
}

- (void)loadSettings {
    NSString *path = SpatialSettingsFilePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [paths.firstObject stringByAppendingPathComponent:@"settings.plist"];
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return;
    }
    
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!dict) return;
    
    if (dict[@"ClockBlur"] != nil) {
        _blurRadius = [dict[@"ClockBlur"] doubleValue];
    }
    if (dict[@"ClockBezelWidth"] != nil) {
        _bezelWidth = [dict[@"ClockBezelWidth"] doubleValue];
    }
    if (dict[@"ClockRefraction"] != nil) {
        _refractionAmount = [dict[@"ClockRefraction"] doubleValue];
    }
    if (dict[@"ClockRefractionIndex"] != nil) {
        _refractionIndex = [dict[@"ClockRefractionIndex"] doubleValue];
    }
}

- (void)saveSettings {
    NSString *dir = @"/var/jb/var/mobile/Library/Application Support/26Lock";
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        dir = @"/var/mobile/Library/Application Support/26Lock";
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *settingsPath = [dir stringByAppendingPathComponent:@"settings.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:settingsPath] ?: [NSMutableDictionary dictionary];
    
    dict[@"ClockBlur"] = @(self.blurRadius);
    dict[@"ClockBezelWidth"] = @(self.bezelWidth);
    dict[@"ClockRefraction"] = @(self.refractionAmount);
    dict[@"ClockRefractionIndex"] = @(self.refractionIndex);
    
    BOOL ok = [dict writeToFile:settingsPath atomically:YES];
    if (!ok) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        settingsPath = [paths.firstObject stringByAppendingPathComponent:@"settings.plist"];
        [dict writeToFile:settingsPath atomically:YES];
    }
    
    @try {
        NSString *laPath = LiquidAssPrefsFilePath();
        NSMutableDictionary *laDict = [NSMutableDictionary dictionaryWithContentsOfFile:laPath] ?: [NSMutableDictionary dictionary];
        laDict[@"Clock.Blur"] = @(self.blurRadius);
        laDict[@"Clock.BezelWidth"] = @(self.bezelWidth);
        laDict[@"Clock.BezelRatio"] = @(self.bezelWidth / 100.0);
        laDict[@"Clock.RefractionScale"] = @(self.refractionAmount);
        laDict[@"Clock.RefractiveIndex"] = @(self.refractionIndex);
        [laDict writeToFile:laPath atomically:YES];
        notify_post("dylv.liquidassprefs/Reload");
    } @catch (...) {}
    
    // live update
    notify_post(kSpatialClockSettingsUpdatedNotification);
}

@end
