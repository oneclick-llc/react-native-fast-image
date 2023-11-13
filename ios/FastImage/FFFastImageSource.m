#import "FFFastImageSource.h"

@implementation FFFastImageSource

- (instancetype)initWithURL:(NSURL *)url
                   priority:(FFFPriority)priority
                    headers:(NSDictionary *)headers
               cacheControl:(FFFCacheControl)cacheControl
                  cacheTier:(FFFCacheTier)cacheTier
{
    self = [super init];
    if (self) {
        _url = url;
        _priority = priority;
        _headers = headers;
        _cacheControl = cacheControl;
        _cacheTier = cacheTier;
    }
    return self;
}

@end
