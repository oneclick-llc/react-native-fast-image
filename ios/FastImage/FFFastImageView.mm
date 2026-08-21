#import "FFFastImageView.h"
#import "FFFastImageViewManager.h"
#import "FFFastImageBlurTransformation.h"
#import <CoreImage/CoreImage.h>
#import <SDWebImage/UIImage+MultiFormat.h>
#import <SDWebImage/UIView+WebCache.h>
// Кодеки здесь не подключаются: их регистрирует [FFFastImageHelper setup:]
// один раз на приложение — см. ниже commonInitUtils.
#import "FFFastImageHelper.h"

@interface FFFastImageView ()

@property(nonatomic, assign) BOOL hasSentOnLoadStart;
@property(nonatomic, assign) BOOL hasCompleted;
@property(nonatomic, assign) BOOL hasErrored;
// Whether the latest change of props requires the image to be reloaded
@property(nonatomic, assign) BOOL needsReload;

@property(nonatomic, strong) NSDictionary* onLoadEvent;

@property(nonatomic, strong) NSDictionary *lastErrorEvent;

@end

@implementation FFFastImageView

static NSString * const kFFFastImageDefaultErrorMessage = @"Load failed";

// Cap of the animated-image frame buffer, in bytes. `0` (the SDWebImage default)
// lets the player size the buffer from device memory — up to `min(total * 0.2,
// free * 0.6)`, which is hundreds of megabytes per animated view.
static const NSUInteger kFFFastImageMaxBufferSize = 8 * 1024 * 1024;

// Decode boxes are rounded UP to a multiple of this many pixels.
//
// The requested thumbnail size is part of SDWebImage's cache key (it appends a
// `…-Thumbnail(WxH)` segment), so handing the decoder the raw layout size mints
// a separate cache entry — and a separate decode — for every pixel of
// incidental variance: per device scale, per container width, per re-layout of
// the same image. Coarse buckets collapse all of those onto one key per URL per
// size class.
//
// Rounding up (never down) is what makes it safe: SDWebImage aspect-fits into
// the box (`preserveAspectRatio` defaults to YES), so a larger box never
// distorts and never blurs — at worst it decodes slightly more pixels than the
// view strictly needs. Each dimension is bucketed independently for the same
// reason.
//
// Kept in step with the JS-side helper (`look-box/utils/imageDecodeSize.utils.ts`),
// which quantizes with the same step and the same rounding direction, and with
// the native waterfall cell's own bucketing.
static const CGFloat kFFFastImageDecodeSizeBucketPx = 128;

static CGFloat FFFastImageBucketedPixels(CGFloat pixels) {
    if (!(pixels > 0)) {
        return kFFFastImageDecodeSizeBucketPx;
    }
    CGFloat buckets = ceil(pixels / kFFFastImageDecodeSizeBucketPx);
    if (buckets < 1) {
        buckets = 1;
    }
    return buckets * kFFFastImageDecodeSizeBucketPx;
}

// Nil-tolerant value comparison: `[nil isEqual:x]` is NO, so a plain `isEqual:`
// would report two absent values as different.
static BOOL FFFastImageObjectsEqual(id lhs, id rhs) {
    return lhs == rhs || [lhs isEqual:rhs];
}

- (void)onLoadEventSend:(UIImage *)image {
    NSDictionary* onLoadEvent = @{
            @"width": [NSNumber numberWithDouble: image.size.width],
            @"height": [NSNumber numberWithDouble: image.size.height]
    };
    #ifdef RCT_NEW_ARCH_ENABLED
        if (_eventEmitter != nullptr) {
            std::dynamic_pointer_cast<const facebook::react::FastImageViewEventEmitter>(_eventEmitter)
                ->onFastImageLoad(facebook::react::FastImageViewEventEmitter::OnFastImageLoad{.width = image.size.width, .height = image.size.height});
          }
    #else
    if (self.onFastImageLoad) {
        self.onFastImageLoad(onLoadEvent);
    }
#endif
}

- (void)onLoadStartEvent {
    #ifdef RCT_NEW_ARCH_ENABLED
        if (_eventEmitter != nullptr) {
            std::dynamic_pointer_cast<const facebook::react::FastImageViewEventEmitter>(_eventEmitter)
            ->onFastImageLoadStart(facebook::react::FastImageViewEventEmitter::OnFastImageLoadStart{});
        }
    #else
        if (self.onFastImageLoadStart) {
            self.onFastImageLoadStart(@{});
            self.hasSentOnLoadStart = YES;
        } else {
            self.hasSentOnLoadStart = NO;
        }
    #endif
}

- (void)onProgressEvent:(NSInteger)receivedSize expectedSize:(NSInteger)expectedSize {
    #ifdef RCT_NEW_ARCH_ENABLED
        if (_eventEmitter != nullptr) {
            std::dynamic_pointer_cast<const facebook::react::FastImageViewEventEmitter>(_eventEmitter)
            ->onFastImageProgress(facebook::react::FastImageViewEventEmitter::OnFastImageProgress{.loaded = static_cast<int>(receivedSize), .total = static_cast<int>(expectedSize)});
        }
    #else
        if (self.onFastImageProgress) {
            self.onFastImageProgress(@{
                @"loaded": @(receivedSize),
                @"total": @(expectedSize)
            });
        }
    #endif
}

- (void)onLoadEndEvent {
    #ifdef RCT_NEW_ARCH_ENABLED
        if (_eventEmitter != nullptr) {
            std::dynamic_pointer_cast<const facebook::react::FastImageViewEventEmitter>(_eventEmitter)
            ->onFastImageLoadEnd(facebook::react::FastImageViewEventEmitter::OnFastImageLoadEnd{});
        }
    #else
    if (self.onFastImageLoadEnd) {
        self.onFastImageLoadEnd(@{});
    }
#endif
}

- (void)onErrorEvent:(NSError *)error {

    NSString *msg = error.localizedDescription ?: kFFFastImageDefaultErrorMessage;
    NSDictionary *event = @{ @"error": msg };
    self.lastErrorEvent = event;

    #ifdef RCT_NEW_ARCH_ENABLED
        if (_eventEmitter != nullptr) {
            std::dynamic_pointer_cast<const facebook::react::FastImageViewEventEmitter>(_eventEmitter)
            ->onFastImageError(facebook::react::FastImageViewEventEmitter::OnFastImageError{.error = static_cast<std::string>([error.localizedDescription UTF8String])});
        }
    #else
        if (self.onFastImageError) {
            self.onFastImageError(@{
                    @"error": error.localizedDescription ?: kFFFastImageDefaultErrorMessage
                }
            );
        }
    #endif
}


- (void)commonInitUtils {
    self.resizeMode = RCTResizeModeCover;
    self.clipsToBounds = YES;
    // Bound the animated frame buffer instead of letting it grow with free memory.
    self.maxBufferSize = kFFFastImageMaxBufferSize;
    // Кодеки и загрузчик кадров — один раз на приложение, а не на каждую вью
    // (апстрим регистрирует их прямо здесь, и они копятся в общем списке по
    // разу на картинку). Размеры кэшей и тиры по-прежнему за
    // [FFFastImageHelper setup:] из AppDelegate.
    [FFFastImageHelper registerDefaults];
}

- (instancetype)initWithFrame:(CGRect)frame {
//     Called on new arch from FFFastImageComponentView
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInitUtils];
    }
    return self;
}

- (id) init {
//     Called on old arch from FFFastImageViewManager
    self = [super init];
    if (self) {
        [self commonInitUtils];
    }
    return self;
}

- (void) setResizeMode: (RCTResizeMode)resizeMode {
    if (_resizeMode != resizeMode) {
        _resizeMode = resizeMode;
        self.contentMode = (UIViewContentMode) resizeMode;
    }
}

- (void) setOnFastImageLoadEnd: (RCTDirectEventBlock)onFastImageLoadEnd {
    _onFastImageLoadEnd = onFastImageLoadEnd;
    if (self.hasCompleted && _onFastImageLoadEnd) {
        _onFastImageLoadEnd(@{});
    }
}

- (void) setOnFastImageLoad: (RCTDirectEventBlock)onFastImageLoad {
    _onFastImageLoad = onFastImageLoad;
    if (self.hasCompleted && _onFastImageLoad) {
        _onFastImageLoad(self.onLoadEvent);
    }
}

- (void) setOnFastImageError: (RCTDirectEventBlock)onFastImageError {
    _onFastImageError = onFastImageError;
    if (self.hasErrored && _onFastImageError) {
        _onFastImageError(self.lastErrorEvent ?: @{ @"error": kFFFastImageDefaultErrorMessage});
    }
}

- (void) setOnFastImageLoadStart: (RCTDirectEventBlock)onFastImageLoadStart {
    if (_source && !self.hasSentOnLoadStart) {
        _onFastImageLoadStart = onFastImageLoadStart;
        if (onFastImageLoadStart) {
            onFastImageLoadStart(@{});
        }
        self.hasSentOnLoadStart = YES;
    } else {
        _onFastImageLoadStart = onFastImageLoadStart;
        self.hasSentOnLoadStart = NO;
    }
}

- (void) setImageColor: (UIColor*)imageColor {
    if (imageColor != nil) {
        _imageColor = imageColor;
        if (super.image) {
            super.image = [self makeImage: super.image withTint: self.imageColor];
        }
    }
}

- (void)setBlurRadius:(CGFloat)blurRadius {
    if (_blurRadius != blurRadius) {
        _blurRadius = blurRadius;
        _needsReload = YES;
    }
}

- (UIImage*) makeImage: (UIImage*)image withTint: (UIColor*)color {
    UIImage* newImage = [image imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size];
    newImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
    [color setFill];
    [newImage drawInRect:CGRectMake(0, 0, image.size.width, newImage.size.height)];
    }];
    return newImage;
}

- (void) setImage: (UIImage*)image {
    if (_blurRadius && _blurRadius > 0) {
        FFFastImageBlurTransformation *transformation =
            [[FFFastImageBlurTransformation alloc] initWithRadius:_blurRadius];
        image = [transformation transform:image];
    }

    if (self.imageColor != nil) {
        super.image = [self makeImage: image withTint: self.imageColor];
    } else {
        super.image = image;
    }
}

- (void) sendOnLoad: (UIImage*)image {
    [self onLoadEventSend:image];
}

// The setters below compare by value, not by pointer: the new architecture
// rebuilds these props from scratch on every props update, so a pointer
// comparison would restart the load on every React re-render.
- (void) setSource: (FFFastImageSource*)source {
    if (!FFFastImageObjectsEqual(_source, source)) {
        _source = source;
        _needsReload = YES;
    }
}

- (void) setResizeSize: (NSDictionary*)resizeSize {
    if (!FFFastImageObjectsEqual(_resizeSize, resizeSize)) {
        _resizeSize = resizeSize;
        _needsReload = YES;
    }
}


- (void) setDefaultSource: (UIImage*)defaultSource {
    // UIImage has no value equality, so this stays an identity comparison — it is
    // only made nil-tolerant for consistency with the setters above.
    if (!FFFastImageObjectsEqual(_defaultSource, defaultSource)) {
        _defaultSource = defaultSource;
        _needsReload = YES;
    }
}

- (void) didSetProps: (NSArray<NSString*>*)changedProps {
    if (_needsReload) {
        [self reloadImage];
    }
}

- (void) reloadImage {
    _needsReload = NO;

    if (_source) {
        // Load base64 images.
        NSString* url = [_source.url absoluteString];
        if (url && [url hasPrefix: @"data:image"]) {
            [self onLoadStartEvent];
            // Use SDWebImage API to support external format like WebP images
            UIImage* image = [UIImage sd_imageWithData: [NSData dataWithContentsOfURL: _source.url]];
            [self setImage: image];
            [self onProgressEvent:1 expectedSize:1];
            self.hasCompleted = YES;
            [self sendOnLoad: image];
            [self onLoadEndEvent];
            return;
        }

        // Set headers.
        NSDictionary* headers = _source.headers;
        SDWebImageDownloaderRequestModifier* requestModifier = [SDWebImageDownloaderRequestModifier requestModifierWithBlock: ^NSURLRequest* _Nullable (NSURLRequest* _Nonnull request) {
            NSMutableURLRequest* mutableRequest = [request mutableCopy];
            for (NSString* header in headers) {
                NSString* value = headers[header];
                [mutableRequest setValue: value forHTTPHeaderField: header];
            }
            return [mutableRequest copy];
        }];
        SDWebImageContext* mutableContext = @{SDWebImageContextDownloadRequestModifier: requestModifier}.mutableCopy;

        if (_resizeSize != NULL) {
            double width = [RCTConvert double:[_resizeSize valueForKey:@"width"]];
            double height = [RCTConvert double:[_resizeSize valueForKey:@"height"]];
            
            // `resizeSize` comes from JS in points; the thumbnail context is
            // specified in pixels, so it has to be scaled for the screen.
            //
            // Bucketed before it enters the context, because the value ends up
            // in the cache key — see `FFFastImageBucketedPixels` above.
            CGFloat scale = UIScreen.mainScreen.scale;
            CGSize pixelSize = CGSizeMake(FFFastImageBucketedPixels(width * scale),
                                          FFFastImageBucketedPixels(height * scale));

            // Thumbnail only, deliberately without an SDImageResizingTransformer:
            // the thumbnail is produced by the decoder at the requested size, while
            // a transformer decodes the image at full pixel size first and then
            // resizes it into a second bitmap — twice the peak memory for the same
            // result — and it appends its own segment to the cache key on top of
            // the thumbnail one.
            [mutableContext setValue:[NSValue valueWithCGSize:pixelSize] forKey:SDWebImageContextImageThumbnailPixelSize];
        }

        // Ссылка на видео: кадр достанет FFFastImageVideoLoader. По расширению
        // он узнаёт видео сам, а признак нужен для ссылок без расширения —
        // тогда вид содержимого знает только вызывающий.
        if (_source.isVideo) {
            [mutableContext setValue:@YES forKey:FFFastImageContextIsVideo];
        }


        // Set priority.
        SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageHandleCookies;
        switch (_source.priority) {
            case FFFPriorityLow:
                options |= SDWebImageLowPriority;
                break;
            case FFFPriorityNormal:
                // Priority is normal by default.
                break;
            case FFFPriorityHigh:
                options |= SDWebImageHighPriority;
                break;
        }

        switch (_source.cacheControl) {
            case FFFCacheControlWeb:
                options |= SDWebImageRefreshCached;
                break;
            case FFFCacheControlCacheOnly:
                options |= SDWebImageFromCacheOnly;
                break;
            case FFFCacheControlImmutable:
                break;
        }
        
        switch (_source.cacheTier) {
            case FFFCacheTierPrimary:
                [mutableContext setValue:[FFFastImageHelper primaryCache] forKey:SDWebImageContextImageCache];
                break;
                
            case FFFCacheTierSecondary:
                [mutableContext setValue:[FFFastImageHelper secondaryCache] forKey:SDWebImageContextImageCache];
                break;
        }

        [self onLoadStartEvent];
        self.hasCompleted = NO;
        self.hasErrored = NO;
        
        SDWebImageContext* context = [NSDictionary dictionaryWithDictionary:mutableContext];
//        NSLog(@"[FastImage] reloadImage context: %@", context);

        [self downloadImage: _source options: options context: context];
    } else if (_defaultSource) {
        [self setImage: _defaultSource];
    }
}

- (void) downloadImage: (FFFastImageSource*)source options: (SDWebImageOptions)options context: (SDWebImageContext*)context {
    __weak FFFastImageView *weakSelf = self; // Always use a weak reference to self in blocks
    // transition: default to none; enable fade if requested
    if (self.transition && [self.transition isEqualToString:@"fade"]) {
        self.sd_imageTransition = SDWebImageTransition.fadeTransition;
    }
    [self sd_setImageWithURL: _source.url
            placeholderImage: _defaultSource
                     options: options
                     context: context
                    progress: ^(NSInteger receivedSize, NSInteger expectedSize, NSURL* _Nullable targetURL) {
        // weakSelf, not self: a strong capture here makes the view own the running
        // operation that owns this block, so a discarded view — and the image it
        // decoded — is never released.
        [weakSelf onProgressEvent:receivedSize expectedSize:expectedSize];
                    } completed: ^(UIImage* _Nullable image,
                    NSError* _Nullable error,
                    SDImageCacheType cacheType,
                    NSURL* _Nullable imageURL) {
                if (error) {
                    weakSelf.hasErrored = YES;
                    [weakSelf onErrorEvent:error];

                    [weakSelf onLoadEndEvent];
                } else {
                    weakSelf.hasCompleted = YES;
                    [weakSelf sendOnLoad: image];
                    [weakSelf onLoadEndEvent];
                }
            }];
}

- (void) dealloc {
    [self sd_cancelCurrentImageLoad];
}

@end
