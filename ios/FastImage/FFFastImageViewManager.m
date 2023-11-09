#import "FFFastImageViewManager.h"
#import "FFFastImageView.h"

#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/SDWebImagePrefetcher.h>
#import <SDWebImagePhotosPlugin/SDWebImagePhotosPlugin.h>
#import <SDWebImageVideoCoder/SDWebImageVideoCoder.h>

@implementation FFFastImageViewManager

RCT_EXPORT_MODULE(FastImageView)


+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (id) init
{
    self = [super init];

    // Supports HTTP URL as well as Photos URL globally
    SDImagePhotosLoader.sharedLoader.requestImageAssetOnly = NO;
    SDImageLoadersManager.sharedManager.loaders = @[SDWebImageDownloader.sharedDownloader, SDImagePhotosLoader.sharedLoader];
    // Replace default manager's loader implementation
    SDWebImageManager.defaultImageLoader = SDImageLoadersManager.sharedManager;
    [SDImageCodersManager.sharedManager addCoder:SDImageVideoCoder.sharedCoder];

    //  SDImagePhotosLoader.sharedLoader.imageRequestOptions = options;
    [SDImageCache.sharedImageCache.config setMaxMemoryCost:100 * 1024 * 1024]; // 100 MB of memory
    [SDImageCache.sharedImageCache.config setMaxDiskSize:200 * 1024 * 1024]; // 200 MB of disk

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

@end
