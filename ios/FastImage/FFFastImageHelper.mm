#import "FFFastImageHelper.h"

static SDImageCache *static_cachePrimary = nil;
static SDImageCache *static_cacheSecondary = nil;
static float static_primaryMemoryCacheSizeMB = 100;
static float static_secondaryMemoryCacheSizeMB = 100;
static float static_primaryDiskCacheSizeMB = 200;
static float static_secondaryDiskCacheSizeMB = 200;

@implementation FFFastImageHelper

/**
 * Кодеки и загрузчик кадров — то, без чего библиотека не отрабатывает свои же
 * обещания.
 *
 * Раньше это лежало внутри `setup:`, а `setup:` зовёт хост из своего
 * AppDelegate. Приложение, которое его не позвало, тихо теряло AVIF, WebP и
 * SVG — то есть половину того, ради чего в подспеке стоят их поды. Ловится это
 * только глазами и только на нужной картинке.
 *
 * Теперь регистрация отдельная и происходит сама, при создании первой вью.
 * `setup:` по-прежнему нужен — но только ради размеров кэшей и тиров.
 */
+ (void)registerDefaults {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // Порядок значим: менеджер спрашивает загрузчики С КОНЦА и берёт
        // первый, который согласился. Видео должно попасть в свой загрузчик
        // раньше, чем качалка возьмёт ссылку себе и потянет ролик целиком.
        NSMutableArray<id<SDImageLoader>> *loaders =
            [SDImageLoadersManager.sharedManager.loaders mutableCopy] ?: [NSMutableArray new];
        if (![loaders containsObject:FFFastImageVideoLoader.sharedLoader]) {
            [loaders addObject:FFFastImageVideoLoader.sharedLoader];
        }
        SDImageLoadersManager.sharedManager.loaders = loaders;
        SDWebImageManager.defaultImageLoader = SDImageLoadersManager.sharedManager;

        // SDWebImageVideoCoder среди кодеков больше нет. Кадр из видео достаёт
        // FFFastImageVideoLoader — читая файл диапазонами, а не получая на вход
        // скачанный целиком ролик, как устроен любой кодек.
        [[SDImageCodersManager sharedManager] addCoder:[SDImageAVIFCoder sharedCoder]];
        [[SDImageCodersManager sharedManager] addCoder:[SDImageWebPCoder sharedCoder]];
#if !defined(DISABLE_SVG) || DISABLE_SVG == 0
        [[SDImageCodersManager sharedManager] addCoder:[SDImageSVGCoder sharedCoder]];
#endif
    });
}

+ (void)setup:(NSDictionary*)params {
    NSLog(@"FFFastImageViewManager setup called");

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
    
    [self registerDefaults];

    // Ссылки Photos глобально (и HTTP, как по умолчанию). Этот загрузчик
    // остаётся здесь: без `setup:` библиотека фотоплёнку и не обещает.
    SDImagePhotosLoader.sharedLoader.requestImageAssetOnly = NO;
    NSMutableArray<id<SDImageLoader>> *loaders =
        [SDImageLoadersManager.sharedManager.loaders mutableCopy] ?: [NSMutableArray new];
    if (![loaders containsObject:SDImagePhotosLoader.sharedLoader]) {
        // Перед загрузчиком видео: у ссылок Photos своя схема, они не спорят.
        [loaders insertObject:SDImagePhotosLoader.sharedLoader atIndex:loaders.count > 0 ? loaders.count - 1 : 0];
    }
    SDImageLoadersManager.sharedManager.loaders = loaders;

    // Replace default manager's loader implementation with customized loader
    SDWebImageManager.defaultImageLoader = SDImageLoadersManager.sharedManager;

    // Setup caches
    // Sizes can be altered by calling [FFFastImageViewManager setup] from your AppDelegate
    static_cachePrimary = [[SDImageCache alloc] initWithNamespace:@"primary"];
    [static_cachePrimary.config setMaxMemoryCost:static_primaryMemoryCacheSizeMB * 1024 * 1024]; // X MB of memory
    [static_cachePrimary.config setMaxDiskSize:static_primaryDiskCacheSizeMB * 1024 * 1024]; // X MB of disk
    
    static_cacheSecondary = [[SDImageCache alloc] initWithNamespace:@"secondary"];
    [static_cacheSecondary.config setMaxMemoryCost:static_secondaryMemoryCacheSizeMB * 1024 * 1024]; // X MB of memory
    [static_cacheSecondary.config setMaxDiskSize:static_secondaryDiskCacheSizeMB * 1024 * 1024]; // X MB of disk
    
    // [SDImageCachesManager sharedManager] comes with default cache instance which is not configured so we replace the whole list
    [[SDImageCachesManager sharedManager] setCaches:@[static_cachePrimary, static_cacheSecondary]];
    SDWebImageManager.defaultImageCache = [SDImageCachesManager sharedManager];
}

+ (SDImageCache *)primaryCache {
    if (static_cachePrimary == nil) {
        NSLog(@"ATTENTION, fast image primary cache not initialized. Call [FFFastImageHelper setup] from your AppDelegate.");
    }
    return static_cachePrimary;
}

+ (SDImageCache *)secondaryCache {
    if (static_cacheSecondary == nil) {
        NSLog(@"ATTENTION, fast image secondary cache not initialized. Call [FFFastImageHelper setup] from your AppDelegate.");
    }
    return static_cacheSecondary;
}

@end
