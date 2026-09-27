#import "../../Shared/LGLiveBackdropView.h"

#define LKLiveBackdropView LGLiveBackdropView
#define kLGFilterTypeClock LGFilterTypeForHostPrefix(@"Clock")

@interface LGLiveBackdropView (SpatialClockCompatibility)
@property (nonatomic, copy) NSString *filterType;
- (void)forceReapplyForRegistrationRace;
@end
