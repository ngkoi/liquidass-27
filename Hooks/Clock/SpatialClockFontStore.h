#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

NS_ASSUME_NONNULL_BEGIN

@interface SpatialClockDigitLayout : NSObject
@property (nonatomic, copy) NSString *character;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) CGPathRef path;
@property (nonatomic, assign) CGRect bounds;
@end

@interface SpatialClockFontStore : NSObject

@property (nonatomic, assign, readonly) BOOL isFontLoaded;
@property (nonatomic, assign, readonly) CGFloat minHeightAxis;
@property (nonatomic, assign, readonly) CGFloat maxHeightAxis;
@property (nonatomic, assign, readonly) CGFloat minWidthAxis;
@property (nonatomic, assign, readonly) CGFloat maxWidthAxis;
@property (nonatomic, assign, readonly) CGFloat minWeightAxis;
@property (nonatomic, assign, readonly) CGFloat maxWeightAxis;
@property (nonatomic, assign, readonly) CGFloat minSoftnessAxis;
@property (nonatomic, assign, readonly) CGFloat maxSoftnessAxis;

+ (instancetype)sharedStore;

- (nullable UIFont *)fontAtPointSize:(CGFloat)pointSize
                              weight:(CGFloat)weight
                               width:(CGFloat)width
                              height:(CGFloat)height
                            softness:(CGFloat)softness;

- (nullable CGPathRef)createGlyphPathForString:(NSString *)string
                                          font:(UIFont *)font
                                        bounds:(nullable CGRect *)outBounds
                                       advance:(nullable CGFloat *)outAdvance CF_RETURNS_RETAINED;

- (nullable CGPathRef)createNormalizedGlyphPathForString:(NSString *)string
                                                    font:(UIFont *)font
                                              canvasSize:(CGSize)canvasSize
                                           contentBounds:(nullable CGRect *)outContentBounds CF_RETURNS_RETAINED;

- (CGFloat)compactContentWidthForString:(NSString *)string;

- (NSArray<SpatialClockDigitLayout *> *)createDigitLayoutsForString:(NSString *)string
                                                               font:(UIFont *)font
                                                         canvasSize:(CGSize)canvasSize
                                                      contentBounds:(nullable CGRect *)outContentBounds;

@end

NS_ASSUME_NONNULL_END
