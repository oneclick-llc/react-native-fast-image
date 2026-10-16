#import "FFFastImageViewModule.h"
#import "FFFastImageSource.h"
#import "FFFastImageHelper.h"
#import "FFFastImageVideoLoader.h"
#import "RCTConvert+FFFastImage.h"

#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/SDWebImageManager.h>
#import <SDWebImage/SDWebImagePrefetcher.h>
#import <SDWebImage/SDWebImageDownloader.h>
#import <SDWebImage/SDWebImageDownloaderRequestModifier.h>

// Every cache the library can be reading from: the two tiers set up by
// `[FFFastImageHelper setup:]`, plus the shared cache that stays in use when the
// host application never called it.
static NSArray<SDImageCache *> *FFFastImageAllCaches(void) {
    NSMutableArray<SDImageCache *> *caches = [NSMutableArray arrayWithObject:SDImageCache.sharedImageCache];
    SDImageCache *primary = [FFFastImageHelper primaryCache];
    if (primary != nil) {
        [caches addObject:primary];
    }
    SDImageCache *secondary = [FFFastImageHelper secondaryCache];
    if (secondary != nil) {
        [caches addObject:secondary];
    }
    return caches;
}

// Prefetch into a specific cache. Without an explicit cache the prefetcher falls
// back to the shared caches manager, whose store policy is "highest only" — the
// image lands in the secondary tier while a primary-tier view looks for it in the
// primary one, so the prefetch can never be hit.
static void FFFastImagePrefetchURLs(NSArray<NSURL *> *urls, SDImageCache *cache) {
    if (urls.count == 0) {
        return;
    }
    SDWebImageMutableContext *context = [NSMutableDictionary dictionary];
    if (cache != nil) {
        context[SDWebImageContextImageCache] = cache;
    }
    [[SDWebImagePrefetcher sharedImagePrefetcher] prefetchURLs:urls
                                                      options:SDWebImageLowPriority
                                                      context:context
                                                     progress:nil
                                                    completed:nil];
}

// The disk cache a view with this tier reads from. Without `[FFFastImageHelper
// setup:]` the view puts no cache into its context and lands in the manager's
// own cache, which is the framework's shared one unless the host replaced it.
static SDImageCache *FFFastImageDiskCacheForTier(FFFCacheTier tier) {
    SDImageCache *cache = tier == FFFCacheTierSecondary
        ? [FFFastImageHelper secondaryCache]
        : [FFFastImageHelper primaryCache];
    if (cache != nil) {
        return cache;
    }
    id<SDImageCache> managerCache = SDWebImageManager.sharedManager.imageCache;
    if ([managerCache isKindOfClass:SDImageCache.class]) {
        return (SDImageCache *)managerCache;
    }
    return SDImageCache.sharedImageCache;
}

// Must not run on the main queue: the existence check is a synchronous hop onto
// the cache's IO queue, behind any store already queued there.
static NSString *FFFastImageExistingCachePath(SDImageCache *cache, NSString *key) {
    if (key.length == 0 || ![cache diskImageDataExistsWithKey:key]) {
        return nil;
    }
    NSString *path = [cache cachePathForKey:key];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (path != nil && [fileManager fileExistsAtPath:path]) {
        return path;
    }
    // SDDiskCache still answers for files written before it started appending
    // the URL's extension to the file name.
    NSString *legacyPath = path.stringByDeletingPathExtension;
    if (legacyPath != nil && [fileManager fileExistsAtPath:legacyPath]) {
        return legacyPath;
    }
    return nil;
}

@implementation FFFastImageViewModule

RCT_EXPORT_MODULE(FastImageViewModule)

RCT_EXPORT_METHOD(preload:(nonnull NSArray<FFFastImageSource *> *)sources)
{
    NSMutableArray<NSURL *> *primaryUrls = [NSMutableArray arrayWithCapacity:sources.count];
    NSMutableArray<NSURL *> *secondaryUrls = [NSMutableArray array];

    [sources enumerateObjectsUsingBlock:^(FFFastImageSource * _Nonnull source, NSUInteger idx, BOOL * _Nonnull stop) {
        [source.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString* header, BOOL *stop) {
            [[SDWebImageDownloader sharedDownloader] setValue:header forHTTPHeaderField:key];
        }];
        if (source.url == nil) {
            return;
        }
        // Same tier the view would read from, so a preloaded image is actually found.
        if (source.cacheTier == FFFCacheTierSecondary) {
            [secondaryUrls addObject:source.url];
        } else {
            [primaryUrls addObject:source.url];
        }
    }];

    FFFastImagePrefetchURLs(primaryUrls, [FFFastImageHelper primaryCache]);
    FFFastImagePrefetchURLs(secondaryUrls, [FFFastImageHelper secondaryCache]);
}

RCT_EXPORT_METHOD(clearMemoryCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    // `sharedImageCache` is neither of the tiers the views use, so clearing only it
    // freed nothing in an application that called `[FFFastImageHelper setup:]`.
    for (SDImageCache *cache in FFFastImageAllCaches()) {
        [cache clearMemory];
    }
    resolve(NULL);
}

RCT_EXPORT_METHOD(clearDiskCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    NSArray<SDImageCache *> *caches = FFFastImageAllCaches();
    dispatch_group_t group = dispatch_group_create();
    for (SDImageCache *cache in caches) {
        dispatch_group_enter(group);
        [cache clearDiskOnCompletion:^(){
            dispatch_group_leave(group);
        }];
    }
    // Resolve once every cache is done, not after the first one.
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        resolve(NULL);
    });
}
RCT_EXPORT_METHOD(getCachedFile:(NSDictionary *)json resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    FFFastImageSource *source = [RCTConvert FFFastImageSource:json];
    NSURL *url = source.url;
    if (url == nil) {
        reject(@"E_INVALID_SOURCE", @"getCachedFile: the source has no uri", nil);
        return;
    }

    dispatch_queue_t workQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    if (url.isFileURL) {
        NSString *filePath = url.path;
        dispatch_async(workQueue, ^{
            if (filePath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:filePath]) {
                resolve(filePath);
            } else {
                reject(@"E_LOAD_FAILED", [NSString stringWithFormat:@"getCachedFile: no file at %@", filePath], nil);
            }
        });
        return;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        reject(@"E_UNSUPPORTED_SOURCE", [NSString stringWithFormat:@"getCachedFile: unsupported uri scheme '%@'", url.scheme], nil);
        return;
    }
    // A video source is cached as a frame decoded by FFFastImageVideoLoader and
    // re-encoded on store; there are no original bytes to hand out.
    if (source.isVideo || [FFFastImageVideoLoader isVideoURL:url]) {
        reject(@"E_UNSUPPORTED_SOURCE", @"getCachedFile: video sources are not supported", nil);
        return;
    }

    // Same loader set-up the view triggers when it is created.
    [FFFastImageHelper registerDefaults];

    SDImageCache *cache = FFFastImageDiskCacheForTier(source.cacheTier);
    NSDictionary *headers = source.headers;
    SDWebImageDownloaderRequestModifier *requestModifier = [SDWebImageDownloaderRequestModifier requestModifierWithBlock:^NSURLRequest * _Nullable(NSURLRequest * _Nonnull request) {
        NSMutableURLRequest *mutableRequest = [request mutableCopy];
        for (NSString *header in headers) {
            [mutableRequest setValue:headers[header] forHTTPHeaderField:header];
        }
        return [mutableRequest copy];
    }];
    SDWebImageContext *context = @{
        SDWebImageContextImageCache: cache,
        SDWebImageContextDownloadRequestModifier: requestModifier,
        // The bytes are what is wanted here: keep a full-size decoded image out
        // of the memory tier.
        SDWebImageContextStoreCacheType: @(SDImageCacheTypeDisk),
    };
    // No thumbnail and no transformer in the context, so this is the view's key
    // for a source without `resizeSize`, and the key its original bytes are
    // stored under in every case.
    NSString *key = [SDWebImageManager.sharedManager cacheKeyForURL:url context:context];

    // The view's own flags, so a joined download decodes once for both. Loader
    // only: a memory hit would answer without the bytes being on disk.
    SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageHandleCookies |
        SDWebImageFromLoaderOnly | SDWebImageWaitStoreCache;
    switch (source.priority) {
        case FFFPriorityLow:
            options |= SDWebImageLowPriority;
            break;
        case FFFPriorityNormal:
            break;
        case FFFPriorityHigh:
            options |= SDWebImageHighPriority;
            break;
    }
    BOOL cacheOnly = source.cacheControl == FFFCacheControlCacheOnly;

    dispatch_async(workQueue, ^{
        NSString *cachedPath = FFFastImageExistingCachePath(cache, key);
        if (cachedPath != nil) {
            resolve(cachedPath);
            return;
        }
        if (cacheOnly) {
            reject(@"E_NOT_CACHED", @"getCachedFile: the image is not in the disk cache", nil);
            return;
        }
        // SDWebImageDownloader keys running downloads by URL, so a display load
        // of the same URL still in flight is joined, not repeated.
        [SDWebImageManager.sharedManager loadImageWithURL:url
                                                  options:options
                                                  context:context
                                                 progress:nil
                                                completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
            if (!finished) {
                return;
            }
            if (error != nil) {
                reject(@"E_LOAD_FAILED", error.localizedDescription ?: @"getCachedFile: load failed", error);
                return;
            }
            // The completion arrives on the main queue.
            dispatch_async(workQueue, ^{
                NSString *loadedPath = FFFastImageExistingCachePath(cache, key);
                if (loadedPath != nil) {
                    resolve(loadedPath);
                } else {
                    reject(@"E_LOAD_FAILED", @"getCachedFile: the loaded image was not stored on disk", nil);
                }
            });
        }];
    });
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeFastImageViewModuleSpecJSI>(params);
}
#endif

@end
