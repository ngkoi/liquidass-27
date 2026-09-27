#import "SpatialClockFontStore.h"
#import "SpatialLogging.h"

@implementation SpatialClockDigitLayout
- (void)dealloc {
    if (_path) {
        CGPathRelease(_path);
        _path = NULL;
    }
}
- (void)setPath:(CGPathRef)path {
    if (_path != path) {
        if (_path) CGPathRelease(_path);
        _path = path ? CGPathRetain(path) : NULL;
    }
}
@end

@interface SpatialClockFontStore ()
@property (nonatomic, assign) CGFontRef graphicsFont;
@property (nonatomic, copy) NSString *postScriptName;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *axisIDs;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSNumber *> *> *axisRanges;
@property (nonatomic, strong) NSCache<NSString *, UIFont *> *fontCache;
@end

@implementation SpatialClockFontStore

+ (instancetype)sharedStore {
    static SpatialClockFontStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[SpatialClockFontStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fontCache = [[NSCache alloc] init];
        _fontCache.countLimit = 512;
        _minHeightAxis = 100.0;
        _maxHeightAxis = 500.0;
        _minWidthAxis = 60.0;
        _maxWidthAxis = 100.0;
        _minWeightAxis = 1.0;
        _maxWeightAxis = 1000.0;
        _minSoftnessAxis = 0.0;
        _maxSoftnessAxis = 100.0;
        [self loadFont];
    }
    return self;
}

- (void)dealloc {
    if (_graphicsFont) {
        CGFontRelease(_graphicsFont);
        _graphicsFont = NULL;
    }
}

- (BOOL)isFontLoaded {
    return (_graphicsFont != NULL && _postScriptName.length > 0);
}

- (NSArray<NSString *> *)candidateFontPaths {
    return @[
        @"/var/jb/Library/Application Support/26Lock/Fonts/SFAdaptiveSoftNumeric-VF.otf",
        @"/var/jb/Library/PreferenceBundles/LiquidAssPrefs.bundle/SFAdaptiveSoftNumeric-VF.otf",
        @"/Library/Application Support/26Lock/Fonts/SFAdaptiveSoftNumeric-VF.otf",
        @"/Library/PreferenceBundles/LiquidAssPrefs.bundle/SFAdaptiveSoftNumeric-VF.otf"
    ];
}

- (void)loadFont {
    NSString *selectedPath = nil;
    for (NSString *candidate in [self candidateFontPaths]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            selectedPath = candidate;
            break;
        }
    }
    
    if (!selectedPath) {
        SpatialLog(@"[FontStore] Font file not found in candidates");
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:selectedPath];
    if (!data.length) {
        SpatialLog(@"[FontStore] Failed to read font data from %@", selectedPath);
        return;
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (!provider) return;
    
    _graphicsFont = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    
    if (!_graphicsFont) {
        SpatialLog(@"[FontStore] Failed to create CGFont from %@", selectedPath);
        return;
    }
    
    CFStringRef psName = CGFontCopyPostScriptName(_graphicsFont);
    if (psName) {
        _postScriptName = CFBridgingRelease(psName);
    }
    
    CFErrorRef regError = NULL;
    BOOL registered = CTFontManagerRegisterGraphicsFont(_graphicsFont, &regError);
    if (!registered && regError) {
        CFIndex code = CFErrorGetCode(regError);
        if (code != kCTFontManagerErrorAlreadyRegistered) {
            SpatialLog(@"[FontStore] Font registration warning: %@", regError);
        }
    }
    if (regError) CFRelease(regError);
    
    // variation axes
    CTFontRef probe = CTFontCreateWithGraphicsFont(_graphicsFont, 60.0, NULL, NULL);
    if (probe) {
        CFArrayRef axesArray = CTFontCopyVariationAxes(probe);
        if (axesArray) {
            NSArray<NSDictionary *> *axes = CFBridgingRelease(axesArray);
            NSMutableDictionary *ids = [NSMutableDictionary dictionary];
            NSMutableDictionary *ranges = [NSMutableDictionary dictionary];
            
            for (NSDictionary *entry in axes) {
                NSNumber *ident = entry[(id)kCTFontVariationAxisIdentifierKey];
                if (!ident) continue;
                
                NSString *key = nil;
                uint32_t tag = ident.unsignedIntValue;
                if (tag == 'wght') key = @"weight";
                else if (tag == 'wdth') key = @"width";
                else if (tag == 'HGHT') key = @"height";
                else if (tag == 'SOFT') key = @"softness";
                
                if (key) {
                    ids[key] = ident;
                    NSNumber *minVal = entry[(id)kCTFontVariationAxisMinimumValueKey] ?: @(0);
                    NSNumber *maxVal = entry[(id)kCTFontVariationAxisMaximumValueKey] ?: @(1000);
                    ranges[key] = @[minVal, maxVal];
                    
                    if ([key isEqualToString:@"height"]) {
                        _minHeightAxis = minVal.doubleValue;
                        _maxHeightAxis = maxVal.doubleValue;
                    } else if ([key isEqualToString:@"width"]) {
                        _minWidthAxis = minVal.doubleValue;
                        _maxWidthAxis = maxVal.doubleValue;
                    } else if ([key isEqualToString:@"weight"]) {
                        _minWeightAxis = minVal.doubleValue;
                        _maxWeightAxis = maxVal.doubleValue;
                    } else if ([key isEqualToString:@"softness"]) {
                        _minSoftnessAxis = minVal.doubleValue;
                        _maxSoftnessAxis = maxVal.doubleValue;
                    }
                }
            }
            _axisIDs = [ids copy];
            _axisRanges = [ranges copy];
        }
        CFRelease(probe);
    }
    
    SpatialLog(@"[FontStore] Loaded variable font '%@' from %@", _postScriptName, selectedPath);
}

- (UIFont *)fontAtPointSize:(CGFloat)pointSize
                     weight:(CGFloat)weight
                      width:(CGFloat)width
                     height:(CGFloat)height
                   softness:(CGFloat)softness {
    if (!self.isFontLoaded) {
        return [UIFont systemFontOfSize:pointSize weight:UIFontWeightBold];
    }
    
    weight   = round(MAX(self.minWeightAxis, MIN(self.maxWeightAxis, weight)));
    width    = round(MAX(self.minWidthAxis, MIN(self.maxWidthAxis, width)));
    height   = round(MAX(self.minHeightAxis, MIN(self.maxHeightAxis, height)));
    softness = round(MAX(self.minSoftnessAxis, MIN(self.maxSoftnessAxis, softness)));
    pointSize = round(MAX(8.0, pointSize) * 2.0) / 2.0;
    
    NSString *cacheKey = [NSString stringWithFormat:@"%.1f|%.1f|%.1f|%.1f|%.1f",
                          pointSize, weight, width, height, softness];
    UIFont *cached = [self.fontCache objectForKey:cacheKey];
    if (cached) return cached;
    
    NSMutableDictionary *variations = [NSMutableDictionary dictionary];
    if (self.axisIDs[@"weight"])   variations[self.axisIDs[@"weight"]]   = @(weight);
    if (self.axisIDs[@"width"])    variations[self.axisIDs[@"width"]]    = @(width);
    if (self.axisIDs[@"height"])   variations[self.axisIDs[@"height"]]   = @(height);
    if (self.axisIDs[@"softness"]) variations[self.axisIDs[@"softness"]] = @(softness);
    
    NSDictionary *attributes = @{
        (id)kCTFontNameAttribute: self.postScriptName,
        (id)kCTFontVariationAttribute: variations
    };
    
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
    if (!descriptor) {
        return [UIFont systemFontOfSize:pointSize weight:UIFontWeightBold];
    }
    
    CTFontRef ctFont = CTFontCreateWithFontDescriptor(descriptor, pointSize, NULL);
    CFRelease(descriptor);
    
    if (!ctFont) {
        return [UIFont systemFontOfSize:pointSize weight:UIFontWeightBold];
    }
    
    UIFont *result = CFBridgingRelease(ctFont);
    [self.fontCache setObject:result forKey:cacheKey];
    return result;
}

- (CGPathRef)createGlyphPathForString:(NSString *)string
                                 font:(UIFont *)font
                               bounds:(CGRect *)outBounds
                              advance:(CGFloat *)outAdvance {
    if (!string.length || !font) return NULL;
    
    NSDictionary *attrs = @{
        (__bridge id)kCTFontAttributeName: font,
        (__bridge id)kCTKernAttributeName: @(3.0)
    };
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:string attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    if (!line) return NULL;
    
    if (outBounds) {
        *outBounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    }
    if (outAdvance) {
        *outAdvance = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    }
    
    CGMutablePathRef combined = CGPathCreateMutable();
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFIndex runCount = CFArrayGetCount(runs);
    
    for (CFIndex r = 0; r < runCount; r++) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
        CTFontRef runFont = (CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        CFIndex count = CTRunGetGlyphCount(run);
        if (!runFont || count <= 0) continue;
        
        CGGlyph *glyphs = calloc((size_t)count, sizeof(CGGlyph));
        CGPoint *positions = calloc((size_t)count, sizeof(CGPoint));
        if (!glyphs || !positions) {
            if (glyphs) free(glyphs);
            if (positions) free(positions);
            continue;
        }
        
        CTRunGetGlyphs(run, CFRangeMake(0, count), glyphs);
        CTRunGetPositions(run, CFRangeMake(0, count), positions);
        
        for (CFIndex i = 0; i < count; i++) {
            CGPathRef glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], NULL);
            if (!glyphPath) continue;
            
            CGAffineTransform shift = CGAffineTransformMakeTranslation(positions[i].x, positions[i].y);
            CGPathAddPath(combined, &shift, glyphPath);
            CGPathRelease(glyphPath);
        }
        
        free(glyphs);
        free(positions);
    }
    
    CFRelease(line);
    return combined;
}

- (CGFloat)compactContentWidthForString:(NSString *)string {
    if (!string.length) return 0.0;
    
    UIFont *font = [self fontAtPointSize:22.0
                                  weight:780.0
                                   width:85.0
                                  height:100.0
                                softness:75.0];
    if (!font) {
        font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    }
    
    NSDictionary *attrs = @{
        (__bridge id)kCTFontAttributeName: font,
        (__bridge id)kCTKernAttributeName: @(0.5)
    };
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:string attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    if (!line) return 0.0;
    
    CGRect glyphBounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    CGFloat advance = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CFRelease(line);
    
    return ceil(MAX(advance, CGRectGetWidth(glyphBounds)));
}

- (NSArray<SpatialClockDigitLayout *> *)createDigitLayoutsForString:(NSString *)string
                                                               font:(UIFont *)font
                                                         canvasSize:(CGSize)canvasSize
                                                      contentBounds:(CGRect *)outContentBounds {
    if (!string.length || !font) return @[];
    
    BOOL isCompact = (canvasSize.height <= 50.0);
    CGFloat kern = isCompact ? 0.5 : 3.0;
    NSDictionary *attrs = @{
        (__bridge id)kCTFontAttributeName: font,
        (__bridge id)kCTKernAttributeName: @(kern)
    };
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:string attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    if (!line) return @[];
    
    CGRect glyphBounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    CGFloat advance = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    
    CGFloat contentWidth = ceil(MAX(advance, CGRectGetWidth(glyphBounds)));
    CGFloat left = isCompact ? 0.0 : MAX(0.0, floor((canvasSize.width - contentWidth) * 0.5));

    
    CGFloat topPadding = 6.0;
    CGFloat targetBaseline = 0.0;
    if (isCompact) {
        // iOS 16 ls date label (CSProminentSubtitleDateView with _UIAnimatingLabel):
        // Container height = 36.0 pt, innerLabel origin.y = 5.0 pt, font = .SFUI-Medium 22pt (ascender: 20.95, capHeight: 15.50)
        // The date text baseline inside CSProminentSubtitleDateView is at y = 5.0 + font.ascender = 25.95 pt
        // In CoreText: y_uikit = -y_ct + targetBaseline. When y_ct = 0 (baseline), y_uikit = targetBaseline
        targetBaseline = 5.0 + font.ascender;
        topPadding = targetBaseline - CGRectGetMaxY(glyphBounds);
    } else {
        targetBaseline = topPadding + CGRectGetMaxY(glyphBounds);
    }
    
    CGAffineTransform transform = CGAffineTransformMake(
        1.0, 0.0,
        0.0, -1.0,
        left - CGRectGetMinX(glyphBounds),
        targetBaseline
    );

    
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFIndex runCount = CFArrayGetCount(runs);
    
    NSMutableDictionary<NSNumber *, id> *pathDict = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *charDict = [NSMutableDictionary dictionary];
    
    for (CFIndex r = 0; r < runCount; r++) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
        CTFontRef runFont = (CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        CFIndex count = CTRunGetGlyphCount(run);
        if (!runFont || count <= 0) continue;
        
        CGGlyph *glyphs = calloc((size_t)count, sizeof(CGGlyph));
        CGPoint *positions = calloc((size_t)count, sizeof(CGPoint));
        CFIndex *stringIndices = calloc((size_t)count, sizeof(CFIndex));
        if (!glyphs || !positions || !stringIndices) {
            if (glyphs) free(glyphs);
            if (positions) free(positions);
            if (stringIndices) free(stringIndices);
            continue;
        }
        
        CTRunGetGlyphs(run, CFRangeMake(0, count), glyphs);
        CTRunGetPositions(run, CFRangeMake(0, count), positions);
        CTRunGetStringIndices(run, CFRangeMake(0, count), stringIndices);
        
        for (CFIndex i = 0; i < count; i++) {
            CGPathRef rawGlyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], NULL);
            if (!rawGlyphPath) continue;
            
            CGAffineTransform shift = CGAffineTransformConcat(
                CGAffineTransformMakeTranslation(positions[i].x, positions[i].y),
                transform
            );
            
            CFIndex charIdx = stringIndices[i];
            NSNumber *key = @(charIdx);
            CGMutablePathRef mutableP = (__bridge CGMutablePathRef)pathDict[key];
            if (!mutableP) {
                mutableP = CGPathCreateMutable();
                pathDict[key] = (__bridge_transfer id)mutableP;
                if (charIdx >= 0 && charIdx < (CFIndex)string.length) {
                    charDict[key] = [string substringWithRange:NSMakeRange(charIdx, 1)];
                }
            }
            CGPathAddPath(mutableP, &shift, rawGlyphPath);
            CGPathRelease(rawGlyphPath);
        }
        
        free(glyphs);
        free(positions);
        free(stringIndices);
    }
    
    CFRelease(line);
    
    NSMutableArray<SpatialClockDigitLayout *> *layouts = [NSMutableArray array];
    NSArray<NSNumber *> *sortedKeys = [[pathDict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    CGRect unionBounds = CGRectZero;
    
    for (NSNumber *key in sortedKeys) {
        CGMutablePathRef mPath = (__bridge CGMutablePathRef)pathDict[key];
        SpatialClockDigitLayout *item = [[SpatialClockDigitLayout alloc] init];
        item.index = key.integerValue;
        item.character = charDict[key] ?: @"";
        item.path = mPath;
        item.bounds = CGPathGetBoundingBox(mPath);
        [layouts addObject:item];
        
        if (CGRectIsEmpty(unionBounds)) {
            unionBounds = item.bounds;
        } else {
            unionBounds = CGRectUnion(unionBounds, item.bounds);
        }
    }
    
    if (outContentBounds) {
        *outContentBounds = unionBounds;
    }
    
    return layouts;
}

- (CGPathRef)createNormalizedGlyphPathForString:(NSString *)string
                                           font:(UIFont *)font
                                     canvasSize:(CGSize)canvasSize
                                  contentBounds:(CGRect *)outContentBounds {
    NSArray<SpatialClockDigitLayout *> *layouts = [self createDigitLayoutsForString:string
                                                                               font:font
                                                                         canvasSize:canvasSize
                                                                      contentBounds:outContentBounds];
    if (!layouts.count) return NULL;
    CGMutablePathRef combined = CGPathCreateMutable();
    for (SpatialClockDigitLayout *layout in layouts) {
        if (layout.path) {
            CGPathAddPath(combined, NULL, layout.path);
        }
    }
    return combined;
}

@end
