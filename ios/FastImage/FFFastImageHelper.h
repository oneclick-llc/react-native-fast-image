#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/SDWebImagePrefetcher.h>
#import <SDWebImagePhotosPlugin/SDWebImagePhotosPlugin.h>
#import "FFFastImageVideoLoader.h"
#import <SDWebImageAVIFCoder/SDImageAVIFCoder.h>
#import <SDWebImageWebPCoder/SDImageWebPCoder.h>
#if !defined(DISABLE_SVG) || DISABLE_SVG == 0
#import <SDWebImageSVGCoder/SDImageSVGCoder.h>
#endif

@interface FFFastImageHelper : NSObject
/**
 * Кодеки (AVIF, WebP, SVG) и загрузчик кадров из видео.
 *
 * Зовётся сама при создании первой вью, идемпотентна. Хосту трогать не нужно.
 */
+ (void)registerDefaults;
 // call this from your AppDelegate in order for customizations to work
+ (void)setup:(NSDictionary *)params;
+ (SDImageCache *)primaryCache;
+ (SDImageCache *)secondaryCache;
@end

