#pragma once

#import <Foundation/Foundation.h>
#import <dlfcn.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (*LGCVRegisterFunction)(NSString *identifier,
                                     NSDictionary * _Nullable configuration,
                                     BOOL nonRemovable,
                                     BOOL hiddenFromPrefs,
                                     NSError * _Nullable * _Nullable error);
typedef BOOL (*LGCVRemoveFunction)(NSString *identifier,
                                   NSError * _Nullable * _Nullable error);

static inline BOOL LGCVRegister(NSString *identifier,
                                NSDictionary * _Nullable configuration,
                                BOOL nonRemovable,
                                BOOL hiddenFromPrefs,
                                NSError * _Nullable * _Nullable error) {
    static LGCVRegisterFunction function;
    if (!function) function = (LGCVRegisterFunction)dlsym(RTLD_DEFAULT, "LGCVRegister");
    if (!function) {
        if (error) *error = [NSError errorWithDomain:@"dylv.liquidass.custom-view-api"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"LiquidAss Custom View API is unavailable"}];
        return NO;
    }
    return function(identifier, configuration, nonRemovable, hiddenFromPrefs, error);
}

static inline BOOL LGCVRemove(NSString *identifier,
                              NSError * _Nullable * _Nullable error) {
    static LGCVRemoveFunction function;
    if (!function) function = (LGCVRemoveFunction)dlsym(RTLD_DEFAULT, "LGCVRemove");
    if (!function) {
        if (error) *error = [NSError errorWithDomain:@"dylv.liquidass.custom-view-api"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"LiquidAss Custom View API is unavailable"}];
        return NO;
    }
    return function(identifier, error);
}

NS_ASSUME_NONNULL_END
