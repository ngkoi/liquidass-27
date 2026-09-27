#import "LGAdjustableBlurView.h"
#import "LGLiveBackdropView.h"

@implementation LGAdjustableBlurView (SpatialClockCompatibility)
- (void)forceRefreshBackdrop { [self applyFilters]; }
@end

@implementation LGLiveBackdropView (SpatialClockCompatibility)
- (NSString *)filterType { return self.lgFilterType; }
- (void)setFilterType:(NSString *)filterType {
    self.lgFilterType = filterType;
    [self applyFilters];
}
- (void)forceReapplyForRegistrationRace { [self applyFilters]; }
@end
