#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Кадр из видео по ссылке — как обычная картинка, без скачивания ролика.
 *
 * Ставится в SDWebImage загрузчиком (`SDImageLoader`), а не кодеком. Разница
 * принципиальная: кодек — тот самый SDWebImageVideoCoder, что стоял здесь
 * раньше, — получает на вход ГОТОВЫЕ данные файла, то есть ради одного кадра
 * ролик качается целиком. Загрузчик решает сам, как добыть данные, и здесь он
 * читает удалённый файл диапазонами силами AVFoundation: `moov` плюс нужные
 * сэмплы. На живом ролике это 4 КБ против 4.7 МБ.
 *
 * Дальше кадр — обычная картинка SDWebImage: её кэш в памяти и на диске,
 * ключ по ссылке, отмена по уходу вью с экрана. Ничего из этого писать заново
 * не нужно.
 */
@interface FFFastImageVideoLoader : NSObject <SDImageLoader>

@property(nonatomic, class, readonly, nonnull) FFFastImageVideoLoader *sharedLoader;

/**
 * Похожа ли ссылка на видео.
 *
 * По расширению: другого способа узнать это ДО запроса нет, а решать нужно
 * именно до — загрузчик выбирается по ссылке. Список только из того, что
 * читает AVFoundation.
 */
+ (BOOL)isVideoURL:(nullable NSURL *)url;

@end

/**
 * Считать ссылку видео, даже если по расширению этого не видно.
 *
 * Ссылки CDN часто без расширения вовсе. Тогда вид содержимого знает
 * вызывающий — он получил его от сервера вместе с mime — и кладёт этот ключ в
 * контекст: `context[FFFastImageContextIsVideo] = @YES`.
 */
FOUNDATION_EXPORT SDWebImageContextOption const FFFastImageContextIsVideo;

/** Позиция кадра в миллисекундах. По умолчанию — самое начало. */
FOUNDATION_EXPORT SDWebImageContextOption const FFFastImageContextVideoFrameTimeMs;

NS_ASSUME_NONNULL_END
