#import "FFFastImageHelper.h"

#import <SDWebImage/SDImageCacheConfig.h>
#import <SDWebImage/SDMemoryCache.h>

#if DEBUG
#include <atomic>
#endif

static SDImageCache *static_cachePrimary = nil;
static SDImageCache *static_cacheSecondary = nil;
static float static_primaryMemoryCacheSizeMB = 100;
static float static_secondaryMemoryCacheSizeMB = 100;
static float static_primaryDiskCacheSizeMB = 200;
static float static_secondaryDiskCacheSizeMB = 200;
/**
 * Count backstops for the two memory tiers (NSCache `countLimit`).
 *
 * The cost limit alone does not bind: SDWebImage charges an animated image the
 * bytes of a SINGLE frame (`SDAnimatedImage`), and a `UIImage` built by
 * `+animatedImageWithImages:` can be charged 0 when its `CGImage` is nil. A
 * cache that under-reports cost never evicts on cost, so an entry count is the
 * only limit that actually holds.
 */
static NSUInteger static_primaryMemoryCacheMaxCount = 256;
static NSUInteger static_secondaryMemoryCacheMaxCount = 64;

/**
 * Defensive ceiling for `SDImageCache.sharedImageCache`.
 *
 * That cache is NOT one of our two tiers — it is the framework default, and it
 * is UNLIMITED out of the box. Anything that binds to it before
 * `setup:` installs `SDWebImageManager.defaultImageCache` (the shared manager
 * reads `defaultImageCache` exactly once, at construction) would then grow
 * without any bound at all. These values cap that worst case.
 */
static const NSUInteger kDefaultSharedCacheMaxMemoryCost = 50 * 1024 * 1024;
static const NSUInteger kDefaultSharedCacheMaxMemoryCount = 64;

#if DEBUG
/**
 * E2 instrumentation (Looky-8890). DEBUG-only — Release builds never compile
 * it, so a Release soak carries no logging cache subclass at all.
 *
 * Answers "which memory cache instance actually receives the stores, and what
 * are its live limits" — the cost/count limits are configured on
 * `SDImageCacheConfig` and propagated to `NSCache` by KVO, so reading them off
 * the cache itself is the only proof they landed.
 *
 * Sampled 1-in-50: the grid stores constantly and an unsampled log would itself
 * distort the measurement.
 */
@interface FFDebugMemoryCache : SDMemoryCache
@end

@implementation FFDebugMemoryCache

- (void)setObject:(id)obj forKey:(id)key cost:(NSUInteger)cost {
    static std::atomic<uint64_t> sampleCounter{0};
    if (sampleCounter.fetch_add(1) % 50 == 0) {
        NSString *keyTail = [key isKindOfClass:NSString.class] ? (NSString *)key : [key description];
        if (keyTail.length > 40) {
            keyTail = [keyTail substringFromIndex:keyTail.length - 40];
        }
        NSLog(@"[Looky8890/E2] store cache=%p costLimit=%lu countLimit=%lu cost=%lu key=…%@",
              (__bridge void *)self,
              (unsigned long)self.totalCostLimit,
              (unsigned long)self.countLimit,
              (unsigned long)cost,
              keyTail);
    }
    [super setObject:obj forKey:key cost:cost];
}

@end
#endif // DEBUG

@interface FFFastImageHelper ()
+ (SDImageCache *)makeTierCacheWithNamespace:(NSString *)ns;
@end

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
    if ([params valueForKey: @"primaryMemoryCacheMaxCount"] != nil) {
        static_primaryMemoryCacheMaxCount = [[params valueForKey: @"primaryMemoryCacheMaxCount"] unsignedIntegerValue];
    }
    if ([params valueForKey: @"secondaryMemoryCacheMaxCount"] != nil) {
        static_secondaryMemoryCacheMaxCount = [[params valueForKey: @"secondaryMemoryCacheMaxCount"] unsignedIntegerValue];
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
    static_cachePrimary = [self makeTierCacheWithNamespace:@"primary"];
    [static_cachePrimary.config setMaxMemoryCost:static_primaryMemoryCacheSizeMB * 1024 * 1024]; // X MB of memory
    [static_cachePrimary.config setMaxMemoryCount:static_primaryMemoryCacheMaxCount]; // X entries
    [static_cachePrimary.config setMaxDiskSize:static_primaryDiskCacheSizeMB * 1024 * 1024]; // X MB of disk

    static_cacheSecondary = [self makeTierCacheWithNamespace:@"secondary"];
    [static_cacheSecondary.config setMaxMemoryCost:static_secondaryMemoryCacheSizeMB * 1024 * 1024]; // X MB of memory
    [static_cacheSecondary.config setMaxMemoryCount:static_secondaryMemoryCacheMaxCount]; // X entries
    [static_cacheSecondary.config setMaxDiskSize:static_secondaryDiskCacheSizeMB * 1024 * 1024]; // X MB of disk

    // The framework-default cache is not part of the tier list, but it exists
    // and it is unlimited unless told otherwise. Give it a bound so a load that
    // reaches it — anything that resolves the shared manager before this method
    // runs, or any caller that queries `sharedImageCache` directly — cannot grow
    // unchecked. Both keys are observed by the live `SDMemoryCache` via KVO, so
    // setting them on the config takes effect immediately.
    [SDImageCache.sharedImageCache.config setMaxMemoryCost:kDefaultSharedCacheMaxMemoryCost];
    [SDImageCache.sharedImageCache.config setMaxMemoryCount:kDefaultSharedCacheMaxMemoryCount];

    // [SDImageCachesManager sharedManager] comes with default cache instance which is not configured so we replace the whole list
    [[SDImageCachesManager sharedManager] setCaches:@[static_cachePrimary, static_cacheSecondary]];
    SDWebImageManager.defaultImageCache = [SDImageCachesManager sharedManager];
}

/**
 * Creates one tier cache.
 *
 * In Release this is exactly what the library builds by default. In DEBUG the
 * instrumented memory cache (E2) is swapped in, which needs an explicit config
 * — and that config must be a COPY: `SDImageCacheConfig.defaultCacheConfig` is
 * a process-wide singleton, so mutating it would push the instrumented class
 * onto every other cache in the app.
 */
+ (SDImageCache *)makeTierCacheWithNamespace:(NSString *)ns {
#if DEBUG
    SDImageCacheConfig *config = [SDImageCacheConfig.defaultCacheConfig copy];
    config.memoryCacheClass = [FFDebugMemoryCache class];
    return [[SDImageCache alloc] initWithNamespace:ns diskCacheDirectory:nil config:config];
#else
    return [[SDImageCache alloc] initWithNamespace:ns];
#endif
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
