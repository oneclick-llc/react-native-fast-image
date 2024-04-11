#import "FFFastImageViewManager.h"
#import "FFFastImageView.h"
#import <SDWebImageWebPCoder/SDImageWebPCoder.h>

static SDImageCache *static_cachePrimary = nil;
static SDImageCache *static_cacheSecondary = nil;
static float static_primaryMemoryCacheSizeMB = 100;
static float static_secondaryMemoryCacheSizeMB = 100;
static float static_primaryDiskCacheSizeMB = 200;
static float static_secondaryDiskCacheSizeMB = 200;

@implementation FFFastImageViewManager

RCT_EXPORT_MODULE(FastImageView)


+ (BOOL)requiresMainQueueSetup {
    return YES;
}

+ (void)setup:(NSDictionary*)params {
    if ([params valueForKey: @"primaryMemoryCacheSizeMB"] != nil) {
        static_primaryMemoryCacheSizeMB = [[params valueForKey: @"primaryMemoryCacheSizeMB"] floatValue];
    }
    if ([params valueForKey: @"secondaryMemoryCacheSizeMB"] != nil) {
        static_secondaryMemoryCacheSizeMB = [[params valueForKey: @"secondaryMemoryCacheSizeMB"] floatValue];
    }
    if ([params valueForKey: @"primaryDiskCacheSizeMB"] != nil) {
        static_primaryDiskCacheSizeMB = [[params valueForKey: @"primaryDiskCacheSizeMB"] floatValue];
    }
    if ([params valueForKey: @"secondaryDiskCacheSizeMB"] != nil) {
        static_secondaryDiskCacheSizeMB = [[params valueForKey: @"secondaryDiskCacheSizeMB"] floatValue];
    }
}

- (id) init
{
    self = [super init];

    // Supports Photos URL globally (and HTTP as by default)
    SDImagePhotosLoader.sharedLoader.requestImageAssetOnly = NO;
    SDImageLoadersManager.sharedManager.loaders = @[SDWebImageDownloader.sharedDownloader, SDImagePhotosLoader.sharedLoader];
    
    // Replace default manager's loader implementation with customized loader
    SDWebImageManager.defaultImageLoader = SDImageLoadersManager.sharedManager;
    
    // Add video coder to global coders manager
    [SDImageCodersManager.sharedManager addCoder:SDImageVideoCoder.sharedCoder];

    // Add WebP coder to global coders manager
    [SDImageCodersManager.sharedManager addCoder:SDImageWebPCoder.sharedCoder];  
    
    // Setup caches
    static_cachePrimary = [[SDImageCache alloc] initWithNamespace:@"primary"];
    [static_cachePrimary.config setMaxMemoryCost:static_primaryMemoryCacheSizeMB * 1024 * 1024]; // 100 MB of memory
    [static_cachePrimary.config setMaxDiskSize:static_primaryDiskCacheSizeMB * 1024 * 1024]; // 200 MB of disk
    
    static_cacheSecondary = [[SDImageCache alloc] initWithNamespace:@"secondary"];
    [static_cacheSecondary.config setMaxMemoryCost:static_secondaryMemoryCacheSizeMB * 1024 * 1024]; // 100 MB of memory
    [static_cacheSecondary.config setMaxDiskSize:static_secondaryDiskCacheSizeMB * 1024 * 1024]; // 200 MB of disk
    
    // [SDImageCachesManager sharedManager] comes with default cache instance which is not configured so we replace the whole list
    [[SDImageCachesManager sharedManager] setCaches:@[static_cachePrimary, static_cacheSecondary]];
    SDWebImageManager.defaultImageCache = [SDImageCachesManager sharedManager];

    return self;
}

- (FFFastImageView*)view {
  return [[FFFastImageView alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(source, FFFastImageSource)
RCT_EXPORT_VIEW_PROPERTY(defaultSource, UIImage)
RCT_EXPORT_VIEW_PROPERTY(resizeMode, RCTResizeMode)
RCT_EXPORT_VIEW_PROPERTY(resizeSize, NSDictionary)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoadStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoad, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoadEnd, RCTDirectEventBlock)
RCT_REMAP_VIEW_PROPERTY(tintColor, imageColor, UIColor)

RCT_EXPORT_METHOD(preload:(nonnull NSArray<FFFastImageSource *> *)sources)
{
    NSMutableArray *urls = [NSMutableArray arrayWithCapacity:sources.count];

    [sources enumerateObjectsUsingBlock:^(FFFastImageSource * _Nonnull source, NSUInteger idx, BOOL * _Nonnull stop) {
        [source.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString* header, BOOL *stop) {
            [[SDWebImageDownloader sharedDownloader] setValue:header forHTTPHeaderField:key];
        }];
        [urls setObject:source.url atIndexedSubscript:idx];
    }];

    [[SDWebImagePrefetcher sharedImagePrefetcher] prefetchURLs:urls];
}

RCT_EXPORT_METHOD(clearMemoryCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    [SDImageCache.sharedImageCache clearMemory];
    resolve(NULL);
}

RCT_EXPORT_METHOD(clearDiskCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    [SDImageCache.sharedImageCache clearDiskOnCompletion:^(){
        resolve(NULL);
    }];
}

+ (SDImageCache *)primaryCache {
    return static_cachePrimary;
}

+ (SDImageCache *)secondaryCache {
    return static_cacheSecondary;
}


@end
