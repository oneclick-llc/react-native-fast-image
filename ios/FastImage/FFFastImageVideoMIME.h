#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// CDN responses can label valid extensionless movies as octet-stream. Only a
// concrete video hint may override detection; local photo posters keep theirs.
static inline NSString * _Nullable FFFastImageVideoMIME(NSString * _Nullable value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *mime = [[value componentsSeparatedByString:@";"].firstObject
                     stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSRange match = [mime rangeOfString:@"^video/[a-z0-9!#$&^_.+\\-]+$"
                               options:NSRegularExpressionSearch];
    return match.location != NSNotFound ? mime : nil;
}

static inline NSDictionary * _Nullable FFFastImageVideoAssetOptions(NSURL * _Nullable url, NSString * _Nullable mime) {
    NSString *type = FFFastImageVideoMIME(mime);
    NSString *scheme = url.scheme.lowercaseString;
    if (type && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        if (@available(iOS 17.0, macOS 14.0, tvOS 17.0, *)) {
            return @{AVURLAssetOverrideMIMETypeKey: type};
        }
    }
    return nil;
}
