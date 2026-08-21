#import "FFFastImageViewModule.h"
#import "FFFastImageSource.h"
#import "FFFastImageHelper.h"

#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/SDWebImagePrefetcher.h>
#import <SDWebImage/SDWebImageDownloader.h>

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
#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeFastImageViewModuleSpecJSI>(params);
}
#endif

@end
