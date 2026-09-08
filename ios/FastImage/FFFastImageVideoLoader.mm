#import "FFFastImageVideoLoader.h"
#import "FFFastImageVideoMIME.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

SDWebImageContextOption const FFFastImageContextIsVideo = @"ffFastImageIsVideo";
SDWebImageContextOption const FFFastImageContextVideoFrameTimeMs = @"ffFastImageVideoFrameTimeMs";
SDWebImageContextOption const FFFastImageContextVideoMIMEType = @"ffFastImageVideoMIMEType";

/**
 * Расширения, которые читает AVFoundation.
 *
 * webm и mkv сюда не входят намеренно: система их не открывает, и лучше
 * честно не взяться за ссылку, чем вернуть ошибку после запроса.
 */
static NSSet<NSString *> *VideoExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        extensions = [NSSet setWithArray:@[@"mp4", @"m4v", @"mov", @"qt", @"mqv", @"3gp", @"3g2"]];
    });
    return extensions;
}

#pragma mark - Реестр идущих извлечений

/**
 * Один и тот же кадр разбирается один раз, сколько бы вью его ни просили.
 *
 * Ключ — «ссылка + размер + позиция». Кэш SDWebImage от этого не спасает: он
 * помогает тому, кто пришёл ПОСЛЕ готового результата, а в списке плитки
 * приходят одновременно. Замер на 30-мегабайтном клипе: две плитки с одной
 * ссылкой без склейки — 33 МБ трафика и два разбора.
 */
@interface FFFastImageVideoFrameRequest : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) AVAssetImageGenerator *generator;
@property(nonatomic, strong) NSMutableArray<SDImageLoaderCompletedBlock> *waiting;
@end

@implementation FFFastImageVideoFrameRequest
@end

static NSMutableDictionary<NSString *, FFFastImageVideoFrameRequest *> *InFlight(void) {
    static NSMutableDictionary *shared;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        shared = [NSMutableDictionary new];
    });
    return shared;
}

/** Один поток на реестр: к нему ходят и с главного, и из потоков AVFoundation. */
static dispatch_queue_t InFlightQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        queue = dispatch_queue_create("com.dylanvann.fastimage.videoframe", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

#pragma mark - Операция

/**
 * То, что SDWebImage отменяет, когда вью уехала с экрана.
 *
 * Отменяется ОДИН ждущий, а не общая работа: разбор остаётся, пока его ждёт
 * хоть кто-то. Иначе в списке ушедшая плитка убивала бы кадр у соседней,
 * которая осталась на экране, — и та не перезапросила бы его уже никогда.
 */
@interface FFFastImageVideoLoaderOperation : NSObject <SDWebImageOperation>
@property(nonatomic, copy, nullable) NSString *key;
@property(nonatomic, copy, nullable) SDImageLoaderCompletedBlock block;
@end

@implementation FFFastImageVideoLoaderOperation

- (void)cancel {
    NSString *key = self.key;
    SDImageLoaderCompletedBlock block = self.block;
    if (key == nil || block == nil) {
        return;
    }
    self.key = nil;
    self.block = nil;

    dispatch_async(InFlightQueue(), ^{
        FFFastImageVideoFrameRequest *request = InFlight()[key];
        if (request == nil) {
            return;
        }
        [request.waiting removeObject:block];
        if (request.waiting.count == 0) {
            // Ждать больше некому — вот теперь работа не нужна.
            [InFlight() removeObjectForKey:key];
            [request.generator cancelAllCGImageGeneration];
        }
    });
}

@end

#pragma mark - Загрузчик

@implementation FFFastImageVideoLoader

+ (FFFastImageVideoLoader *)sharedLoader {
    static FFFastImageVideoLoader *loader;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        loader = [[FFFastImageVideoLoader alloc] init];
    });
    return loader;
}

+ (BOOL)isVideoURL:(NSURL *)url {
    if (url == nil) {
        return NO;
    }
    NSString *extension = url.pathExtension.lowercaseString;
    if (extension.length == 0) {
        return NO;
    }
    return [VideoExtensions() containsObject:extension];
}

#pragma mark - SDImageLoader

- (BOOL)canRequestImageForURL:(NSURL *)url {
    return [FFFastImageVideoLoader isVideoURL:url];
}

- (BOOL)canRequestImageForURL:(NSURL *)url options:(SDWebImageOptions)options context:(SDWebImageContext *)context {
    if ([context[FFFastImageContextIsVideo] boolValue]) {
        return YES;
    }
    return [self canRequestImageForURL:url];
}

- (id<SDWebImageOperation>)requestImageWithURL:(NSURL *)url
                                       options:(SDWebImageOptions)options
                                       context:(SDWebImageContext *)context
                                      progress:(SDImageLoaderProgressBlock)progressBlock
                                     completed:(SDImageLoaderCompletedBlock)completedBlock {
    FFFastImageVideoLoaderOperation *operation = [FFFastImageVideoLoaderOperation new];
    if (url == nil || completedBlock == nil) {
        if (completedBlock) {
            completedBlock(nil, nil, [NSError errorWithDomain:SDWebImageErrorDomain
                                                         code:SDWebImageErrorInvalidURL
                                                     userInfo:nil], YES);
        }
        return operation;
    }

    // Размер берётся из того же ключа контекста, который выставляет `resizeSize`.
    // То есть проп, придуманный для картинок, работает и для кадров: 4K-кадр не
    // разворачивается в память ради плитки в сотню точек.
    NSValue *thumbnailSize = context[SDWebImageContextImageThumbnailPixelSize];
    CGSize maximumSize = thumbnailSize != nil ? thumbnailSize.CGSizeValue : CGSizeZero;
    double timeMs = [context[FFFastImageContextVideoFrameTimeMs] doubleValue];
    NSString *mime = FFFastImageVideoMIME(context[FFFastImageContextVideoMIMEType]);
    NSString *key = [NSString stringWithFormat:@"%@|%.0fx%.0f|%.0f|%@",
                     url.absoluteString, maximumSize.width, maximumSize.height, timeMs, mime ?: @""];

    SDImageLoaderCompletedBlock waiter = [completedBlock copy];
    operation.key = key;
    operation.block = waiter;

    __block BOOL joined = NO;
    __block FFFastImageVideoFrameRequest *request = nil;
    dispatch_sync(InFlightQueue(), ^{
        FFFastImageVideoFrameRequest *running = InFlight()[key];
        if (running != nil) {
            [running.waiting addObject:waiter];
            joined = YES;
            return;
        }
        request = [FFFastImageVideoFrameRequest new];
        request.key = key;
        request.waiting = [NSMutableArray arrayWithObject:waiter];
        InFlight()[key] = request;
    });
    if (joined) {
        return operation;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:FFFastImageVideoAssetOptions(url, mime)];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    // Снятое портретом видео лежит в файле повёрнутым, а поворот записан в
    // дорожке. Без этого кадр вышел бы боком.
    generator.appliesPreferredTrackTransform = YES;
    // Допуск бесконечный — берётся БЛИЖАЙШИЙ ключевой кадр. Точный заставил бы
    // декодировать всё от предыдущего ключевого: качать больше, считать
    // дольше, а для превью разницы не видно.
    generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
    generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
    if (maximumSize.width > 0 && maximumSize.height > 0) {
        generator.maximumSize = maximumSize;
    }
    request.generator = generator;

    void (^finish)(UIImage *_Nullable, NSError *_Nullable) = ^(UIImage *_Nullable frame, NSError *_Nullable failure) {
        __block NSArray<SDImageLoaderCompletedBlock> *waiting = nil;
        dispatch_sync(InFlightQueue(), ^{
            FFFastImageVideoFrameRequest *finished = InFlight()[key];
            waiting = [finished.waiting copy];
            [InFlight() removeObjectForKey:key];
        });
        for (SDImageLoaderCompletedBlock block in waiting) {
            // Данных наружу нет намеренно: кадра как файла не существует, он
            // собран из кусков ролика. Дисковый кэш SDWebImage закодирует его
            // сам — тем же путём, что и любую полученную картинку.
            block(frame, nil, failure, YES);
        }
    };

    CMTime time = CMTimeMakeWithSeconds(timeMs / 1000.0, NSEC_PER_SEC);
    [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:time]]
                                    completionHandler:^(CMTime requested,
                                                        CGImageRef _Nullable image,
                                                        CMTime actual,
                                                        AVAssetImageGeneratorResult result,
                                                        NSError *_Nullable error) {
        if (result != AVAssetImageGeneratorSucceeded || image == NULL) {
            // Отменённое извлечение — не ошибка, но реестр всё равно нужно
            // освободить: иначе ключ останется висеть, и следующий запрос той
            // же плитки будет ждать работы, которой уже нет.
#ifdef DEBUG
            if (result != AVAssetImageGeneratorCancelled) {
                NSLog(@"[FFFastImageVideoLoader] кадр не достался: %@ — %@", url, error);
            }
#endif
            finish(nil, error ?: [NSError errorWithDomain:SDWebImageErrorDomain
                                                     code:SDWebImageErrorInvalidDownloadOperation
                                                 userInfo:nil]);
            return;
        }
        finish([UIImage imageWithCGImage:image], nil);
    }];

    return operation;
}

- (BOOL)shouldBlockFailedURLWithURL:(NSURL *)url error:(NSError *)error {
    // Не поднялась сеть или ролик ещё доезжает на сервер — это не повод
    // запомнить ссылку битой навсегда.
    return NO;
}

- (BOOL)shouldBlockFailedURLWithURL:(NSURL *)url
                              error:(NSError *)error
                            options:(SDWebImageOptions)options
                            context:(SDWebImageContext *)context {
    return NO;
}

@end
