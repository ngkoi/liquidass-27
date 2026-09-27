#import "SpatialLiquidClockView.h"
#import "SpatialClockFontStore.h"
#import "SpatialClockSettings.h"
#import "SpatialLogging.h"
#import "LGAdjustableBlurView.h"
#import "LGLiveBackdropView.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static CGImageRef LGClockGenerateSpecularImageForPath(CGPathRef path, CGSize size, CGFloat bezelWidth) {
    if (!path || size.width <= 0.0 || size.height <= 0.0) return NULL;
    
    //  scaling shits (u dont need to understand this)
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale < 2.0) scale = 2.0;
    uint32_t width = (uint32_t)ceil(size.width * scale);
    uint32_t height = (uint32_t)ceil(size.height * scale);
    size_t totalPixels = (size_t)width * height;
    if (!totalPixels) return NULL;

    static uint8_t *s_alphaBuf = NULL;
    static size_t s_alphaCap = 0;
    static uint32_t *s_specularBuf = NULL;
    static size_t s_specularCap = 0;

    if (totalPixels > s_alphaCap) {
        uint8_t *resized = (uint8_t *)realloc(s_alphaBuf, totalPixels);
        if (!resized) return NULL;
        s_alphaBuf = resized;
        s_alphaCap = totalPixels;
    }

    size_t specularBytes = totalPixels * sizeof(uint32_t);
    if (specularBytes > s_specularCap) {
        uint32_t *resized = (uint32_t *)realloc(s_specularBuf, specularBytes);
        if (!resized) return NULL;
        s_specularBuf = resized;
        s_specularCap = specularBytes;
    }

    memset(s_alphaBuf, 0, totalPixels);
    memset(s_specularBuf, 0, specularBytes);

    CGRect pathBox = CGPathGetBoundingBox(path);
    if (CGRectIsEmpty(pathBox)) return NULL;

    int pad = (int)ceil(fmaxf(4.0f, (float)(bezelWidth * scale / 4.0f)));
    int minX = MAX(1, (int)floor(pathBox.origin.x * scale) - pad);
    int maxX = MIN((int)width - 2, (int)ceil(CGRectGetMaxX(pathBox) * scale) + pad);
    int minY = MAX(1, (int)floor(pathBox.origin.y * scale) - pad);
    int maxY = MIN((int)height - 2, (int)ceil(CGRectGetMaxY(pathBox) * scale) + pad);

    CGContextRef context = CGBitmapContextCreate(s_alphaBuf, width, height, 8, width, NULL,
                                                 (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) return NULL;

    CGContextSetAllowsAntialiasing(context, true);
    CGContextSetShouldAntialias(context, true);

    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, scale, -scale);
    CGContextAddPath(context, path);
    CGContextSetGrayFillColor(context, 1.0, 1.0);
    CGContextFillPath(context);
    CGContextRelease(context);

    float bFactor = (bezelWidth > 0.0f) ? (float)(bezelWidth / 12.0f) : 1.0f;
    int keyWeight = (int)(195.0f * bFactor);
    int fillWeight = (int)(55.0f * bFactor);

    if (minX <= maxX && minY <= maxY) {
        for (int y = minY; y <= maxY; y++) {
            const uint8_t *pAbove = s_alphaBuf + (y - 1) * width;
            const uint8_t *pCurr  = s_alphaBuf + y * width;
            const uint8_t *pBelow = s_alphaBuf + (y + 1) * width;
            uint32_t *pSpec       = s_specularBuf + y * width;

            for (int x = minX; x <= maxX; x++) {
                uint8_t c = pCurr[x];
                if (c == 0) continue;

                int tl = pAbove[x - 1], t = pAbove[x], tr = pAbove[x + 1];
                int l  = pCurr[x - 1],                 r  = pCurr[x + 1];
                int bl = pBelow[x - 1], b = pBelow[x], br = pBelow[x + 1];

                int gx = (tr + (r << 1) + br) - (tl + (l << 1) + bl);
                int gy = (bl + (b << 1) + br) - (tl + (t << 1) + tr);

                if (gx == 0 && gy == 0) continue;

                int dirProj = gx + gy;
                int val = (dirProj > 0) ? ((dirProj * keyWeight) >> 10) : (((-dirProj) * fillWeight) >> 10);

                if (val > 0) {
                    val = (val * (int)c) >> 8;
                    uint32_t h = (uint32_t)MIN(255, val);
                    pSpec[x] = (h << 24) | (h << 16) | (h << 8) | h;
                }
            }
        }
    }

    static CGColorSpaceRef s_colorSpace = NULL;
    static dispatch_once_t s_csOnce;
    dispatch_once(&s_csOnce, ^{
        s_colorSpace = CGColorSpaceCreateDeviceRGB();
    });

    CGContextRef specCtx = CGBitmapContextCreate(s_specularBuf, width, height, 8, width * 4,
                                                 s_colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGImageRef img = specCtx ? CGBitmapContextCreateImage(specCtx) : NULL;
    if (specCtx) CGContextRelease(specCtx);

    return img;
}



#pragma mark - Vibrancy Boost View

@interface SpatialVibrancyBoostView : UIView
- (void)applyFilters;
@end

@implementation SpatialVibrancyBoostView
+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        [self applyFilters];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
}

- (void)applyFilters {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;
    
    @try {
        [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@YES forKey:@"ignoresScreenClip"];
        [layer setValue:@NO forKey:@"disablesOccludedBackdropBlurs"];
        [layer setValue:[NSString stringWithFormat:@"dylv.liquidclock.vibrancy.%p", self] forKey:@"groupName"];
        [layer setValue:@"dylv.liquidclock" forKey:@"groupNamespace"];
        [layer setValue:@(0.35) forKey:@"scale"];
        
        if (layer.filters.count >= 3) return;
        
        Class filterCls = NSClassFromString(@"CAFilter");
        if (!filterCls) return;
        
        NSMutableArray *filters = [NSMutableArray array];
        
        // vibrance boost
        id satFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorSaturate");
        if (satFilter) {
            @try { [satFilter setValue:@(1.85) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:satFilter];
        }
        
        // Luminosity
        id brightFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorBrightness");
        if (brightFilter) {
            @try { [brightFilter setValue:@(0.16) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:brightFilter];
        }
        
        // Subtle contrast
        id contrastFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorContrast");
        if (contrastFilter) {
            @try { [contrastFilter setValue:@(1.06) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:contrastFilter];
        }
        
        layer.filters = filters;
    } @catch (NSException *e) {}
}

- (void)forceRefreshBackdrop {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;
    @try {
        [layer setValue:@YES forKey:@"ignoresScreenClip"];
        [layer setValue:@NO forKey:@"disablesOccludedBackdropBlurs"];
        [self applyFilters];
        [layer setNeedsDisplay];
    } @catch (...) {}
}
@end

#pragma mark - SpatialLiquidClockView

@interface SpatialLiquidClockView ()
@property (nonatomic, strong) UIView *glassContainerView;
@property (nonatomic, strong) LKAdjustableBlurView *blurView;
@property (nonatomic, strong) SpatialVibrancyBoostView *vibrancyView;
@property (nonatomic, strong) LKLiveBackdropView *refractionView;
@property (nonatomic, strong) UIView *tintWashView;

@property (nonatomic, strong) CAShapeLayer *glyphMaskLayer;
@property (nonatomic, strong) CALayer *specularHighlightLayer;
@property (nonatomic, copy) NSArray<SpatialClockDigitLayout *> *currentDigitLayouts;
@property (nonatomic, assign) BOOL isTransitioning;
@property (nonatomic, strong) NSDate *lastUpdateTime;

@property (nonatomic, assign) CGFloat fullExpandedHeight;

@property (nonatomic, copy) NSString *lastRenderKey;
@property (nonatomic, assign) CGSize lastLayoutSize;
@property (nonatomic, assign) CFTimeInterval lastSpecularRenderTime;
@property (nonatomic, assign) CGFloat lastLoggedProgress;
@end

@implementation SpatialLiquidClockView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        
        _compressionProgress = 1.0;
        _userScale = 1.0;
        _userWeight = 780.0;
        _userSoftness = 75.0;
        _fullExpandedHeight = 330.0;
        
        _blurRadius = 9.0;
        _bezelWidth = 12.0;
        _refractionAmount = 2.60;
        _refractionIndex = 1.60;
        
        [self setupLayers];
        [self updateCurrentTimeFromDate];

    }
    return self;
}

- (void)applySettings:(id)settingsObj {
    if (!settingsObj) return;
    SpatialClockSettings *settings = (SpatialClockSettings *)settingsObj;
    
    _blurRadius = settings.blurRadius;
    _bezelWidth = settings.bezelWidth;
    _refractionAmount = settings.refractionAmount;
    _refractionIndex = settings.refractionIndex;
    
    if (self.blurView) {
        self.blurView.blurRadius = self.blurRadius;
    }
    if (self.refractionView) {
        self.refractionView.alpha = (self.refractionAmount > 0.05) ? 1.0 : 0.0;
    }
    
    self.lastRenderKey = nil;
    [self updateClockForceSpecular:YES];
}

- (void)setBlurRadius:(CGFloat)blurRadius {
    if (fabs(_blurRadius - blurRadius) > 0.01) {
        _blurRadius = blurRadius;
        if (self.blurView) {
            self.blurView.blurRadius = blurRadius;
        }
        self.lastRenderKey = nil;
        [self updateClock];
    }
}

- (void)setBezelWidth:(CGFloat)bezelWidth {
    if (fabs(_bezelWidth - bezelWidth) > 0.01) {
        _bezelWidth = bezelWidth;
        self.lastRenderKey = nil;
        [self updateClockForceSpecular:YES];
    }
}

- (void)setRefractionAmount:(CGFloat)refractionAmount {
    if (fabs(_refractionAmount - refractionAmount) > 0.01) {
        _refractionAmount = refractionAmount;
        if (self.refractionView) {
            self.refractionView.alpha = (refractionAmount > 0.05) ? 1.0 : 0.0;
        }
        self.lastRenderKey = nil;
        [self updateClockForceSpecular:YES];
    }
}

- (void)setRefractionIndex:(CGFloat)refractionIndex {
    if (fabs(_refractionIndex - refractionIndex) > 0.01) {
        _refractionIndex = refractionIndex;
    }
}

- (void)setupLayers {
    NSDictionary *nullActions = @{
        @"bounds": [NSNull null],
        @"position": [NSNull null],
        @"frame": [NSNull null],
        @"transform": [NSNull null]
    };
    
    _glassContainerView = [[UIView alloc] initWithFrame:self.bounds];
    _glassContainerView.userInteractionEnabled = NO;
    _glassContainerView.backgroundColor = [UIColor clearColor];
    _glassContainerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _glassContainerView.layer.actions = nullActions;
    [self addSubview:_glassContainerView];
    
    _blurView = [[LKAdjustableBlurView alloc] initWithFrame:_glassContainerView.bounds blurRadius:_blurRadius];
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.layer.actions = nullActions;
    [_glassContainerView addSubview:_blurView];
    
    _vibrancyView = [[SpatialVibrancyBoostView alloc] initWithFrame:_glassContainerView.bounds];
    _vibrancyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _vibrancyView.layer.actions = nullActions;
    [_glassContainerView addSubview:_vibrancyView];
    
    _refractionView = [[LKLiveBackdropView alloc] initWithFrame:_glassContainerView.bounds];
    _refractionView.filterType = kLGFilterTypeClock;
    _refractionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _refractionView.layer.actions = nullActions;
    _refractionView.alpha = (_refractionAmount > 0.05) ? 1.0 : 0.0;
    [_glassContainerView addSubview:_refractionView];
    
    _tintWashView = [[UIView alloc] initWithFrame:_glassContainerView.bounds];
    _tintWashView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _tintWashView.userInteractionEnabled = NO;
    _tintWashView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tintWashView.layer.actions = nullActions;
    [_glassContainerView addSubview:_tintWashView];
    
    _glyphMaskLayer = [CAShapeLayer layer];
    _glyphMaskLayer.frame = self.bounds;
    _glyphMaskLayer.fillColor = [UIColor whiteColor].CGColor;
    _glyphMaskLayer.actions = @{ @"path": [NSNull null], @"bounds": [NSNull null], @"position": [NSNull null] };
    _glassContainerView.layer.mask = _glyphMaskLayer;
    
    // plusL
    _specularHighlightLayer = [CALayer layer];
    _specularHighlightLayer.frame = self.bounds;
    _specularHighlightLayer.contentsGravity = kCAGravityResize;
    _specularHighlightLayer.contentsScale = [UIScreen mainScreen].scale;
    _specularHighlightLayer.opacity = 0.82;
    _specularHighlightLayer.actions = @{
        @"contents": [NSNull null],
        @"bounds": [NSNull null],
        @"position": [NSNull null],
        @"opacity": [NSNull null]
    };
    Class filterCls = NSClassFromString(@"CAFilter");
    if (filterCls) {
        id plusL = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"plusL");
        _specularHighlightLayer.compositingFilter = plusL ?: @"plusL";
    } else {
        _specularHighlightLayer.compositingFilter = @"plusL";
    }
    [self.layer addSublayer:_specularHighlightLayer];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (bounds.size.width > 0.0 && bounds.size.height > 0.0) {
        if (!CGSizeEqualToSize(_lastLayoutSize, bounds.size)) {
            _lastLayoutSize = bounds.size;
        }
        [self updateClock];
    }
}


- (void)updateCurrentTimeFromDate {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm";
    });
    self.timeString = [formatter stringFromDate:[NSDate date]] ?: @"12:00";
}

- (void)setTimeString:(NSString *)timeString {
    if (!timeString.length) return;
    if ([_timeString isEqualToString:timeString]) return;
    
    NSString *oldTimeString = [_timeString copy];
    _timeString = [timeString copy];
    
    BOOL canAnimate = NO;
    if ((self.isLiveOnScreen || self.window != nil) &&
        oldTimeString.length == timeString.length &&
        _currentDigitLayouts.count == timeString.length &&
        !_isTransitioning) {
        canAnimate = YES;
    }
    self.lastUpdateTime = [NSDate date];
    
    if (canAnimate) {
        [self animateTransitionFromTimeString:oldTimeString toTimeString:timeString];
    } else {
        [self updateClock];
    }
}

- (void)setIsInlineWithDate:(BOOL)isInlineWithDate {
    if (_isInlineWithDate != isInlineWithDate) {
        _isInlineWithDate = isInlineWithDate;
        self.lastRenderKey = nil;
        if (isInlineWithDate) {
            self.blurView.blurRadius = 4.0;
        } else {
            self.blurView.blurRadius = 9.0;
        }
        [self updateClock];
    }
}

- (void)setCompressionProgress:(CGFloat)compressionProgress {
    CGFloat clamped = MAX(0.0, MIN(1.0, compressionProgress));
    if (fabs(_compressionProgress - clamped) > 0.003 || (clamped >= 0.999 && _compressionProgress < 0.999) || (clamped <= 0.001 && _compressionProgress > 0.001)) {
        _compressionProgress = clamped;
        [self updateClock];
    }
}

static const char *kLGClockSharedMaskPath =
    "/var/mobile/Library/Accessibility/liquidglass-clock-mask-shared.bin";
static const size_t kLGClockSharedMaskCapacity = 32 * 1024 * 1024;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint64_t capacity;
    uint64_t sequence;
    uint64_t generation;
    uint32_t width;
    uint32_t height;
    uint64_t pixelBytes;
    float imageScale;
    float bezelWidthPoints;
} LGClockSharedMaskHeader;

static void *LGClockSharedMaskMapping(void) {
    static void *mapping = MAP_FAILED;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size_t size = sizeof(LGClockSharedMaskHeader) + kLGClockSharedMaskCapacity;
        int fd = open(kLGClockSharedMaskPath, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
        if (fd < 0) {
            SpatialLog(@"[LiquidClock] Shared mask open failed path=%s errno=%d", kLGClockSharedMaskPath, errno);
            return;
        }
        if (ftruncate(fd, (off_t)size) == 0) {
            fchmod(fd, 0666);
            mapping = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            if (mapping == MAP_FAILED) {
                SpatialLog(@"[LiquidClock] Shared mask mmap failed bytes=%zu errno=%d", size, errno);
            }
        } else {
            SpatialLog(@"[LiquidClock] Shared mask truncate failed bytes=%zu errno=%d", size, errno);
        }
        close(fd);
    });
    return mapping;
}

static void computeMeijsterEDT(const uint8_t *binaryMask, uint8_t *distOut, int w, int h) {
    if (!binaryMask || !distOut || w <= 0 || h <= 0) return;
    
    static int *s_gBuf = NULL;
    static size_t s_gBufCap = 0;
    size_t gNeeded = (size_t)w * h * sizeof(int);
    if (gNeeded > s_gBufCap) {
        int *resized = (int *)realloc(s_gBuf, gNeeded);
        if (!resized) return;
        s_gBuf = resized;
        s_gBufCap = gNeeded;
    }
    int *g = s_gBuf;
    int infinity = w + h + 1000;
    
    for (int x = 0; x < w; x++) {
        g[x] = (binaryMask[x] < 128) ? 0 : infinity;
        for (int y = 1; y < h; y++) {
            int idx = y * w + x;
            g[idx] = (binaryMask[idx] < 128) ? 0 : (g[(y - 1) * w + x] + 1);
        }
        for (int y = h - 2; y >= 0; y--) {
            int idx = y * w + x;
            if (g[(y + 1) * w + x] + 1 < g[idx]) {
                g[idx] = g[(y + 1) * w + x] + 1;
            }
        }
    }
    
    static int *s_sBuf = NULL;
    static int *s_tBuf = NULL;
    static size_t s_stCap = 0;
    size_t stNeeded = (size_t)w * sizeof(int);
    if (stNeeded > s_stCap) {
        int *rs = (int *)realloc(s_sBuf, stNeeded);
        int *rt = (int *)realloc(s_tBuf, stNeeded);
        if (!rs || !rt) return;
        s_sBuf = rs;
        s_tBuf = rt;
        s_stCap = stNeeded;
    }
    int *s = s_sBuf;
    int *t = s_tBuf;
    
    for (int y = 0; y < h; y++) {
        int q = 0;
        s[0] = 0;
        t[0] = 0;
        for (int u = 1; u < w; u++) {
            while (q >= 0) {
                int i = s[q];
                int gi = g[y * w + i];
                int gu = g[y * w + u];
                int f_q = (t[q] - i) * (t[q] - i) + gi * gi;
                int f_u = (t[q] - u) * (t[q] - u) + gu * gu;
                if (f_q > f_u) q--;
                else break;
            }
            if (q < 0) {
                q = 0;
                s[0] = u;
            } else {
                int i = s[q];
                int gi = g[y * w + i];
                int gu = g[y * w + u];
                int w_sep = 1 + (u * u - i * i + gu * gu - gi * gi) / (2 * (u - i));
                if (w_sep < w) {
                    q++;
                    s[q] = u;
                    t[q] = w_sep;
                }
            }
        }
        for (int u = w - 1; u >= 0; u--) {
            int idx = y * w + u;
            if (binaryMask[idx] < 128) {
                distOut[idx] = 0;
            } else {
                int i = s[q];
                int gi = g[y * w + i];
                float d = sqrtf((float)((u - i) * (u - i) + gi * gi));
                float alpha = (float)binaryMask[idx] / 255.0f;
                if (alpha < 0.99f && d <= 1.5f) {
                    d = alpha;
                }
                int val = (int)roundf(d * 16.0f);
                distOut[idx] = (uint8_t)(val > 255 ? 255 : (val < 0 ? 0 : val));
            }
            if (u == t[q]) q--;
        }
    }
}

- (BOOL)publishSharedMaskForPath:(CGPathRef)path size:(CGSize)size scale:(CGFloat)scale bezelWidth:(CGFloat)bezelWidth {
    if (!path || size.width <= 0.0 || size.height <= 0.0) return NO;
    uint32_t width = (uint32_t)ceil(size.width * scale);
    uint32_t height = (uint32_t)ceil(size.height * scale);
    size_t bytes = (size_t)width * height;
    if (!bytes || bytes > kLGClockSharedMaskCapacity) return NO;

    static uint8_t *s_maskAlphaBuf = NULL;
    static size_t s_maskAlphaCap = 0;
    if (bytes > s_maskAlphaCap) {
        uint8_t *resized = (uint8_t *)realloc(s_maskAlphaBuf, bytes);
        if (!resized) return NO;
        s_maskAlphaBuf = resized;
        s_maskAlphaCap = bytes;
    }
    memset(s_maskAlphaBuf, 0, bytes);
    CGContextRef context = CGBitmapContextCreate(s_maskAlphaBuf, width, height, 8, width,
                                                  NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) return NO;
    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, scale, -scale);
    CGContextAddPath(context, path);
    CGContextSetGrayFillColor(context, 1.0, 1.0);
    CGContextFillPath(context);
    CGContextRelease(context);

    static uint8_t *s_maskDistBuf = NULL;
    static size_t s_maskDistCap = 0;
    if (bytes > s_maskDistCap) {
        uint8_t *resized = (uint8_t *)realloc(s_maskDistBuf, bytes);
        if (!resized) return NO;
        s_maskDistBuf = resized;
        s_maskDistCap = bytes;
    }
    computeMeijsterEDT(s_maskAlphaBuf, s_maskDistBuf, width, height);

    void *mapping = LGClockSharedMaskMapping();
    if (!mapping || mapping == MAP_FAILED) return NO;

    static uint64_t s_maskGeneration = 0;
    LGClockSharedMaskHeader *header = (LGClockSharedMaskHeader *)mapping;
    uint64_t sequence = __atomic_load_n(&header->sequence, __ATOMIC_RELAXED);
    if (sequence & 1) sequence++;
    __atomic_store_n(&header->sequence, sequence + 1, __ATOMIC_RELEASE);
    header->magic = 0x4c474d34;
    header->version = 2;
    header->capacity = kLGClockSharedMaskCapacity;
    header->generation = ++s_maskGeneration;
    header->width = width;
    header->height = height;
    header->pixelBytes = bytes;
    header->imageScale = (float)scale;
    header->bezelWidthPoints = (float)bezelWidth;
    memcpy((uint8_t *)mapping + sizeof(*header), s_maskDistBuf, bytes);
    __atomic_store_n(&header->sequence, sequence + 2, __ATOMIC_RELEASE);
    return YES;
}

- (void)notifySettled {
    if (_isTransitioning) {
        return;
    }
    self.lastRenderKey = nil;
    [self updateClockForceSpecular:YES];
    [self.blurView forceRefreshBackdrop];
    [self.vibrancyView forceRefreshBackdrop];
    [self.refractionView forceReapplyForRegistrationRace];
}

- (void)updateClock {
    [self updateClockForceSpecular:NO];
}

- (void)updateClockForceSpecular:(BOOL)forceSpecular {
    @autoreleasepool {
        if (!self.timeString.length || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
        
        if (_isTransitioning) {
            return;
        }
        
        CGFloat p = self.compressionProgress;
        CGFloat heightAxis = 100.0;
        CGFloat widthAxis = 100.0;
        CGFloat pointSize = 84.0;
        
        if (self.isInlineWithDate) {
            pointSize = 22.0;
            heightAxis = 100.0;
            widthAxis = 85.0;
        } else {
            CGFloat t = MAX(0.0, MIN(1.0, p));
            
            heightAxis = 100.0 + (380.0 - 100.0) * t;
            
            CGFloat sNorm = MAX(0.0, MIN(1.0, t / 0.60));
            pointSize = (74.0 + (120.0 - 74.0) * sNorm) * self.userScale;
            
            CGFloat wNorm = MAX(0.0, MIN(1.0, t / 0.50));
            widthAxis = 75.0 + (100.0 - 75.0) * wNorm;
        }
        
        NSString *renderKey = [NSString stringWithFormat:@"%@|%.1f|%.1f|%.1f|%.1f|%.1f|%d|%.1f|%.1f|%.1f|%.1f|%.1f",
                               self.timeString, pointSize, self.userWeight, widthAxis, heightAxis, self.userSoftness, self.isInlineWithDate, self.bounds.size.width, self.bounds.size.height, self.blurRadius, self.bezelWidth, self.refractionAmount];
        if ([renderKey isEqualToString:self.lastRenderKey]) return;
        self.lastRenderKey = renderKey;

        SpatialClockFontStore *store = [SpatialClockFontStore sharedStore];
        UIFont *font = [store fontAtPointSize:pointSize
                                       weight:self.userWeight
                                        width:widthAxis
                                       height:heightAxis
                                     softness:self.userSoftness];
        if (!font) return;
        
        CGRect contentBounds = CGRectZero;
        NSArray<SpatialClockDigitLayout *> *layouts = [store createDigitLayoutsForString:self.timeString
                                                                                    font:font
                                                                              canvasSize:self.bounds.size
                                                                           contentBounds:&contentBounds];
        if (!layouts.count) return;
        
        if (!self.isInlineWithDate && self.bounds.size.width > 100.0 && self.bounds.size.height > 100.0) {
            CGFloat maxAllowedWidth = self.bounds.size.width - 44.0; 
            CGFloat maxAllowedHeight = self.bounds.size.height - 16.0;
            CGFloat currentWidth = CGRectGetWidth(contentBounds);
            CGFloat currentHeight = CGRectGetHeight(contentBounds);
            
            if ((currentWidth > maxAllowedWidth || currentHeight > maxAllowedHeight) && currentWidth > 10.0 && currentHeight > 10.0) {
                CGFloat scaleW = maxAllowedWidth / currentWidth;
                CGFloat scaleH = maxAllowedHeight / currentHeight;
                CGFloat scale = MIN(scaleW, scaleH);
                
                pointSize = floor(pointSize * scale);
                font = [store fontAtPointSize:pointSize
                                       weight:self.userWeight
                                        width:widthAxis
                                       height:heightAxis
                                     softness:self.userSoftness];
                layouts = [store createDigitLayoutsForString:self.timeString
                                                        font:font
                                                  canvasSize:self.bounds.size
                                               contentBounds:&contentBounds];
            }
        }
        
        self.currentDigitLayouts = layouts;
        
        // Update measured heights
        _currentContentHeight = CGRectGetHeight(contentBounds);
        if (p >= 0.95 && _currentContentHeight > 100.0) {
            _fullExpandedHeight = _currentContentHeight;
        }

        CGMutablePathRef glyphPath = CGPathCreateMutable();
        for (SpatialClockDigitLayout *dl in layouts) {
            if (dl.path) {
                CGPathAddPath(glyphPath, NULL, dl.path);
            }
        }
        
        CGFloat maxY = CGRectGetMaxY(contentBounds);
        if (maxY <= 0.0) maxY = self.bounds.size.height;
        CGFloat activeHeight = ceil(maxY + 12.0);
        if (activeHeight > self.bounds.size.height) activeHeight = self.bounds.size.height;
        if (activeHeight < 40.0) activeHeight = 40.0;
        CGRect activeRect = CGRectMake(0.0, 0.0, self.bounds.size.width, activeHeight);
        CGRect activeBounds = CGRectMake(0.0, 0.0, activeRect.size.width, activeRect.size.height);

        // Render specular highlight synchronously on every frame so rims stay 100% in lockstep with clock resizing
        CGImageRef specularImg = LGClockGenerateSpecularImageForPath(glyphPath, activeRect.size, self.bezelWidth);
        
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        
        self.glassContainerView.frame = activeRect;
        self.blurView.frame = activeBounds;
        self.vibrancyView.frame = activeBounds;
        self.refractionView.frame = activeBounds;
        self.tintWashView.frame = activeBounds;
        
        self.glyphMaskLayer.frame = activeBounds;
        self.glyphMaskLayer.path = glyphPath;
        [self.glyphMaskLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
        
        self.specularHighlightLayer.frame = activeRect;
        self.specularHighlightLayer.contents = specularImg ? (__bridge id)specularImg : nil;
        [self.specularHighlightLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
        
        [CATransaction commit];
        
        static CGFloat s_lastPublishedP = -1.0;
        if (forceSpecular || fabs(p - s_lastPublishedP) > 0.04 || p >= 0.999 || p <= 0.001) {
            s_lastPublishedP = p;
            [self publishSharedMaskForPath:glyphPath size:activeBounds.size scale:1.0 bezelWidth:self.bezelWidth];
        }
        
        if (specularImg) CGImageRelease(specularImg);
        CGPathRelease(glyphPath);
        
        // logs
        if (forceSpecular || fabs(p - self.lastLoggedProgress) > 0.15) {
            self.lastLoggedProgress = p;
            SpatialLog(@"[LiquidClock] Updated text=%@ size=%.1f h=%.1f w=%.1f progress=%.2f bounds=%@",
                       self.timeString, pointSize, heightAxis, widthAxis, p, NSStringFromCGRect(contentBounds));
        }
    }
}


- (void)animateTransitionFromTimeString:(NSString *)oldTimeString toTimeString:(NSString *)newTimeString {
    if (oldTimeString.length != newTimeString.length) {
        [self updateClock];
        return;
    }
    
    CGFloat p = self.compressionProgress;
    CGFloat heightAxis = 100.0;
    CGFloat pointSize = 84.0;
    CGFloat widthAxis = 100.0;
    
    if (self.isInlineWithDate) {
        pointSize = 22.0;
        heightAxis = 100.0;
        widthAxis = 85.0;
    } else {
        heightAxis = 100.0 + (380.0 - 100.0) * MAX(0.0, MIN(1.0, p));
        CGFloat sNorm = MAX(0.0, MIN(1.0, p / 0.60));
        pointSize = (74.0 + (120.0 - 74.0) * sNorm) * self.userScale;
        CGFloat wNorm = MAX(0.0, MIN(1.0, p / 0.50));
        widthAxis = 75.0 + (100.0 - 75.0) * wNorm;
    }
    
    self.lastRenderKey = [NSString stringWithFormat:@"%@|%.1f|%.1f|%.1f|%.1f|%.1f|%d|%.1f|%.1f",
                          newTimeString, pointSize, self.userWeight, widthAxis, heightAxis, self.userSoftness, self.isInlineWithDate, self.bounds.size.width, self.bounds.size.height];

    
    SpatialClockFontStore *store = [SpatialClockFontStore sharedStore];
    UIFont *font = [store fontAtPointSize:pointSize
                                   weight:self.userWeight
                                    width:widthAxis
                                   height:heightAxis
                                 softness:self.userSoftness];
    if (!font) {
        [self updateClock];
        return;
    }
    
    CGRect contentBounds = CGRectZero;
    NSArray<SpatialClockDigitLayout *> *newLayouts = [store createDigitLayoutsForString:newTimeString
                                                                                   font:font
                                                                             canvasSize:self.bounds.size
                                                                          contentBounds:&contentBounds];
    if (newLayouts.count != newTimeString.length) {
        [self updateClock];
        return;
    }
    
    if (!self.isInlineWithDate && self.bounds.size.width > 100.0) {
        CGFloat maxAllowedWidth = self.bounds.size.width - 44.0; 
        CGFloat currentWidth = CGRectGetWidth(contentBounds);
        if (currentWidth > maxAllowedWidth && currentWidth > 10.0) {
            CGFloat scale = maxAllowedWidth / currentWidth;
            pointSize = floor(pointSize * scale);
            font = [store fontAtPointSize:pointSize
                                   weight:self.userWeight
                                    width:widthAxis
                                   height:heightAxis
                                 softness:self.userSoftness];
            newLayouts = [store createDigitLayoutsForString:newTimeString
                                                       font:font
                                                 canvasSize:self.bounds.size
                                              contentBounds:&contentBounds];
            if (newLayouts.count != newTimeString.length) {
                [self updateClock];
                return;
            }
        }
    }
    
    _currentContentHeight = CGRectGetHeight(contentBounds);

    if (p >= 0.99) {
        _fullExpandedHeight = _currentContentHeight;
    }
    
    CGMutablePathRef newCombinedPath = CGPathCreateMutable();
    for (SpatialClockDigitLayout *dl in newLayouts) {
        if (dl.path) CGPathAddPath(newCombinedPath, NULL, dl.path);
    }
    
    NSMutableArray<NSNumber *> *changedIndices = [NSMutableArray array];
    NSMutableArray<NSNumber *> *unchangedIndices = [NSMutableArray array];
    for (NSUInteger i = 0; i < newTimeString.length; i++) {
        if ([oldTimeString characterAtIndex:i] != [newTimeString characterAtIndex:i]) {
            [changedIndices addObject:@(i)];
        } else {
            [unchangedIndices addObject:@(i)];
        }
    }
    
    if (!changedIndices.count) {
        CGPathRelease(newCombinedPath);
        return;
    }
    
    _isTransitioning = YES;
    NSArray<SpatialClockDigitLayout *> *oldLayouts = [_currentDigitLayouts copy];
    _currentDigitLayouts = newLayouts;
    
    CFTimeInterval nowMediaTime = CACurrentMediaTime();
    CFTimeInterval phase2Delay = 0.192;
    CFTimeInterval phase2Duration = 0.78;
    CAMediaTimingFunction *appleDecel = [CAMediaTimingFunction functionWithControlPoints:0.16 :1.0 :0.3 :1.0];
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    self.glyphMaskLayer.path = NULL;
    self.specularHighlightLayer.contents = nil;
    [self.glyphMaskLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [self.specularHighlightLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    
    for (NSNumber *numIdx in unchangedIndices) {
        NSUInteger idx = numIdx.unsignedIntegerValue;
        SpatialClockDigitLayout *dl = (idx < oldLayouts.count) ? oldLayouts[idx] : newLayouts[idx];
        if (!dl.path) continue;
        
        CAShapeLayer *sMask = [CAShapeLayer layer];
        sMask.frame = self.bounds;
        sMask.fillColor = [UIColor whiteColor].CGColor;
        sMask.path = dl.path;
        sMask.actions = @{ @"path": [NSNull null], @"opacity": [NSNull null] };
        [self.glyphMaskLayer addSublayer:sMask];
        
        CGImageRef sImg = LGClockGenerateSpecularImageForPath(dl.path, self.bounds.size, self.bezelWidth);
        if (sImg) {
            CALayer *sSpec = [CALayer layer];
            sSpec.frame = self.bounds;
            sSpec.contentsScale = UIScreen.mainScreen.scale;
            sSpec.contentsGravity = kCAGravityResize;
            sSpec.contents = (__bridge id)sImg;
            sSpec.actions = @{ @"opacity": [NSNull null] };
            [self.specularHighlightLayer addSublayer:sSpec];
            CGImageRelease(sImg);
        }
    }
    
    NSMutableArray<CAShapeLayer *> *oldMaskLayers = [NSMutableArray array];
    NSMutableArray<CALayer *> *oldSpecLayers = [NSMutableArray array];
    for (NSNumber *numIdx in changedIndices) {
        NSUInteger idx = numIdx.unsignedIntegerValue;
        if (idx >= oldLayouts.count) continue;
        SpatialClockDigitLayout *oldDL = oldLayouts[idx];
        if (!oldDL.path) continue;
        
        CAShapeLayer *oMask = [CAShapeLayer layer];
        oMask.frame = self.bounds;
        oMask.fillColor = [UIColor whiteColor].CGColor;
        oMask.path = oldDL.path;
        oMask.opacity = 1.0;
        oMask.actions = @{ @"path": [NSNull null] };
        [self.glyphMaskLayer addSublayer:oMask];
        [oldMaskLayers addObject:oMask];
        
        CGImageRef oImg = LGClockGenerateSpecularImageForPath(oldDL.path, self.bounds.size, self.bezelWidth);
        if (oImg) {
            CALayer *oSpec = [CALayer layer];
            oSpec.frame = self.bounds;
            oSpec.contentsScale = UIScreen.mainScreen.scale;
            oSpec.contentsGravity = kCAGravityResize;
            oSpec.contents = (__bridge id)oImg;
            oSpec.opacity = 1.0;
            oSpec.actions = @{};
            [self.specularHighlightLayer addSublayer:oSpec];
            [oldSpecLayers addObject:oSpec];
            CGImageRelease(oImg);
        }
    }
    
    NSMutableArray<CAShapeLayer *> *newMaskLayers = [NSMutableArray array];
    NSMutableArray<CALayer *> *newSpecLayers = [NSMutableArray array];
    for (NSNumber *numIdx in changedIndices) {
        NSUInteger idx = numIdx.unsignedIntegerValue;
        if (idx >= newLayouts.count) continue;
        SpatialClockDigitLayout *newDL = newLayouts[idx];
        if (!newDL.path) continue;
        
        CAShapeLayer *nMask = [CAShapeLayer layer];
        nMask.frame = self.bounds;
        nMask.fillColor = [UIColor whiteColor].CGColor;
        nMask.path = newDL.path;
        nMask.opacity = 0.0;
        nMask.actions = @{ @"path": [NSNull null] };
        [self.glyphMaskLayer addSublayer:nMask];
        [newMaskLayers addObject:nMask];
        
        CALayer *nSpec = nil;
        CGImageRef nImg = LGClockGenerateSpecularImageForPath(newDL.path, self.bounds.size, self.bezelWidth);
        if (nImg) {
            nSpec = [CALayer layer];
            nSpec.frame = self.bounds;
            nSpec.contentsScale = UIScreen.mainScreen.scale;
            nSpec.contentsGravity = kCAGravityResize;
            nSpec.contents = (__bridge id)nImg;
            nSpec.opacity = 0.0;
            nSpec.actions = @{};
            [self.specularHighlightLayer addSublayer:nSpec];
            [newSpecLayers addObject:nSpec];
            CGImageRelease(nImg);
        }
        
        CGRect digitBounds = newDL.bounds;
        CGFloat pad = 16.0;
        CGRect digitFrame = CGRectMake(digitBounds.origin.x - 8.0,
                                       digitBounds.origin.y - pad,
                                       digitBounds.size.width + 16.0,
                                       digitBounds.size.height + pad * 2.0);
        
        CAGradientLayer *maskGrad = [CAGradientLayer layer];
        maskGrad.frame = digitFrame;
        maskGrad.startPoint = CGPointMake(0.5, 1.0); // bottom
        maskGrad.endPoint   = CGPointMake(0.5, 0.0); // top
        maskGrad.colors = @[
            (id)[UIColor whiteColor].CGColor,
            (id)[UIColor whiteColor].CGColor,
            (id)[UIColor clearColor].CGColor
        ];
        maskGrad.locations = @[ @(0.0), @(0.0), @(0.15) ];
        nMask.mask = maskGrad;
        
        CABasicAnimation *wipeAnim = [CABasicAnimation animationWithKeyPath:@"locations"];
        wipeAnim.fromValue = @[ @(0.0), @(0.0), @(0.15) ];
        wipeAnim.toValue   = @[ @(0.85), @(1.0), @(1.0) ];
        wipeAnim.duration = phase2Duration;
        wipeAnim.beginTime = nowMediaTime + phase2Delay;
        wipeAnim.fillMode = kCAFillModeBoth;
        wipeAnim.timingFunction = appleDecel;
        wipeAnim.removedOnCompletion = NO;
        [maskGrad addAnimation:wipeAnim forKey:@"bottomToTopWipe"];
        
        CABasicAnimation *bloomAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        bloomAnim.fromValue = @(0.0);
        bloomAnim.toValue = @(1.0);
        bloomAnim.duration = 0.35;
        bloomAnim.beginTime = nowMediaTime + phase2Delay;
        bloomAnim.fillMode = kCAFillModeBoth;
        bloomAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        bloomAnim.removedOnCompletion = NO;
        [nMask addAnimation:bloomAnim forKey:@"bloom"];
        
        CABasicAnimation *slideAnim = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        slideAnim.fromValue = @(18.0);
        slideAnim.toValue = @(0.0);
        slideAnim.duration = phase2Duration;
        slideAnim.beginTime = nowMediaTime + phase2Delay;
        slideAnim.timingFunction = appleDecel;
        slideAnim.fillMode = kCAFillModeBoth;
        slideAnim.removedOnCompletion = NO;
        [nMask addAnimation:slideAnim forKey:@"slideUp"];
        
        nMask.opacity = 1.0;
        
        if (nSpec) {
            CAGradientLayer *specGrad = [CAGradientLayer layer];
            specGrad.frame = digitFrame;
            specGrad.startPoint = CGPointMake(0.5, 1.0); // bottom
            specGrad.endPoint   = CGPointMake(0.5, 0.0); // top
            specGrad.colors = @[
                (id)[UIColor whiteColor].CGColor,
                (id)[UIColor whiteColor].CGColor,
                (id)[UIColor clearColor].CGColor
            ];
            specGrad.locations = @[ @(0.0), @(0.0), @(0.15) ];
            nSpec.mask = specGrad;
            [specGrad addAnimation:wipeAnim forKey:@"bottomToTopWipe"];
            [nSpec addAnimation:bloomAnim forKey:@"bloom"];
            [nSpec addAnimation:slideAnim forKey:@"slideUp"];
            nSpec.opacity = 1.0;
        }
    }
    
    [CATransaction commit];
    
    for (CAShapeLayer *m in oldMaskLayers) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(1.0);
        fade.toValue = @(0.0);
        fade.duration = phase2Delay;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        fade.fillMode = kCAFillModeBoth;
        fade.removedOnCompletion = NO;
        [m addAnimation:fade forKey:@"fadeOut"];
        m.opacity = 0.0;
    }
    for (CALayer *s in oldSpecLayers) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(1.0);
        fade.toValue = @(0.0);
        fade.duration = phase2Delay;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        fade.fillMode = kCAFillModeBoth;
        fade.removedOnCompletion = NO;
        [s addAnimation:fade forKey:@"fadeOut"];
        s.opacity = 0.0;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(phase2Delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (CAShapeLayer *m in oldMaskLayers) [m removeFromSuperlayer];
        for (CALayer *s in oldSpecLayers) [s removeFromSuperlayer];
    });
    
    // Publish new combined mask to shared memory for backboardd Metal refraction
    [self publishSharedMaskForPath:newCombinedPath size:self.bounds.size scale:1.0 bezelWidth:self.bezelWidth];
    CGPathRelease(newCombinedPath);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((phase2Delay + phase2Duration + 0.10) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_isTransitioning) {
            self->_isTransitioning = NO;
            self.lastRenderKey = nil;
            [self updateClockForceSpecular:YES];
        }
    });

    
    SpatialLog(@"[LiquidClock] Time transition started: %@ -> %@ (animating indices: %@)",
               oldTimeString, newTimeString, changedIndices);
}

@end
