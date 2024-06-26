#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, FFFPriority) {
    FFFPriorityLow,
    FFFPriorityNormal,
    FFFPriorityHigh
};

typedef NS_ENUM(NSInteger, FFFCacheControl) {
    FFFCacheControlImmutable,
    FFFCacheControlWeb,
    FFFCacheControlCacheOnly
};

typedef NS_ENUM(NSInteger, FFFCacheTier) {
    FFFCacheTierPrimary,
    FFFCacheTierSecondary
};

// Object containing an image uri and metadata.
@interface FFFastImageSource : NSObject

// uri for image, or base64
@property (nonatomic) NSURL* url;
// priority for image request
@property (nonatomic) FFFPriority priority;
// headers for the image request
@property (nonatomic) NSDictionary *headers;
// cache control mode
@property (nonatomic) FFFCacheControl cacheControl;
// cache tier
@property(nonatomic) FFFCacheTier cacheTier;

- (instancetype)initWithURL:(NSURL *)url
                   priority:(FFFPriority)priority
                    headers:(NSDictionary *)headers
               cacheControl:(FFFCacheControl)cacheControl
                  cacheTier:(FFFCacheTier)cacheTier;

@end
