#import "FFFastImageSource.h"

@implementation FFFastImageSource

- (instancetype)initWithURL:(NSURL *)url
                   priority:(FFFPriority)priority
                    headers:(NSDictionary *)headers
               cacheControl:(FFFCacheControl)cacheControl
                  cacheTier:(FFFCacheTier)cacheTier
                    isVideo:(BOOL)isVideo
{
    self = [super init];
    if (self) {
        _url = url;
        _priority = priority;
        _headers = headers;
        _cacheControl = cacheControl;
        _cacheTier = cacheTier;
        _isVideo = isVideo;
    }
    return self;
}

- (BOOL)isEqualToFastImageSource:(FFFastImageSource *)other {
    if (other == nil) {
        return NO;
    }
    if (other == self) {
        return YES;
    }
    if (_priority != other.priority ||
        _cacheControl != other.cacheControl ||
        _cacheTier != other.cacheTier ||
        _isVideo != other.isVideo) {
        return NO;
    }
    if (_url != other.url && ![_url isEqual:other.url]) {
        return NO;
    }
    if (_headers != other.headers && ![_headers isEqual:other.headers]) {
        return NO;
    }
    if (_mimeType != other.mimeType && ![_mimeType isEqual:other.mimeType]) {
        return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[FFFastImageSource class]]) {
        return NO;
    }
    return [self isEqualToFastImageSource:(FFFastImageSource *)object];
}

- (NSUInteger)hash {
    return _url.hash ^ _headers.hash ^ (NSUInteger)_priority ^ ((NSUInteger)_cacheControl << 2) ^
           ((NSUInteger)_cacheTier << 4) ^ ((NSUInteger)_isVideo << 6) ^ _mimeType.hash;
}

@end
