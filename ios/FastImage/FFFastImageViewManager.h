#import <React/RCTViewManager.h>

#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/SDWebImagePrefetcher.h>
#import <SDWebImagePhotosPlugin/SDWebImagePhotosPlugin.h>
#import <SDWebImageVideoCoder/SDWebImageVideoCoder.h>

@interface FFFastImageViewManager : RCTViewManager
+(SDImageCache*)primaryCache;
+(SDImageCache*)secondaryCache;
@end
