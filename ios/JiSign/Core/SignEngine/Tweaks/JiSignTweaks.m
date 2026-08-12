#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 配置（从 JiSignConfig.plist 读取）
static BOOL gBlockUpdateCheck = NO;
static BOOL gBlockClipboard = NO;
static BOOL gBlockJailbreak = NO;
static BOOL gBlockAppJump = NO;

#pragma mark - Swizzle Helper

static void swizzle(Class cls, SEL orig, SEL swiz) {
    Method a = class_getInstanceMethod(cls, orig);
    Method b = class_getInstanceMethod(cls, swiz);
    if (a && b) method_exchangeImplementations(a, b);
}

#pragma mark - UIPasteboard Hook (移除剪贴板检测)

@interface UIPasteboard (JiSign)
@end
@implementation UIPasteboard (JiSign)
- (NSString *)jisign_string { return nil; }
- (BOOL)jisign_hasStrings { return NO; }
- (BOOL)jisign_hasURLs { return NO; }
@end

#pragma mark - UIApplication Hook (移除 App 跳转检测)

@interface UIApplication (JiSign)
@end
@implementation UIApplication (JiSign)
- (BOOL)jisign_canOpenURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    // 只允许标准 scheme
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
        [scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"mailto"]) {
        return [self jisign_canOpenURL:url]; // 调用原始方法
    }
    return NO; // 其他 scheme 返回 NO
}
@end

#pragma mark - NSFileManager Hook (移除越狱检测)

@interface NSFileManager (JiSign)
@end
@implementation NSFileManager (JiSign)
- (BOOL)jisign_fileExistsAtPath:(NSString *)path {
    // 拦截越狱检测路径
    static NSArray *jailbreakPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        jailbreakPaths = @[
            @"/Applications/Cydia.app",
            @"/usr/sbin/sshd",
            @"/bin/bash",
            @"/usr/bin/ssh",
            @"/etc/apt",
            @"/private/var/lib/apt/",
            @"/private/var/lib/cydia",
            @"/private/var/stash",
            @"/usr/libexec/sftp-server",
            @"/usr/bin/cycript",
            @"/usr/local/bin/cycript",
            @"/usr/lib/libcycript.dylib",
            @"/var/cache/apt",
            @"/var/lib/apt",
            @"/var/lib/cydia",
            @"/var/log/syslog",
            @"/var/tmp/cydia.log",
            @"/bin/sh",
            @"/private/var/mobile/Library/SBSettings/Themes",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries",
            @"/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist"
        ];
    });

    for (NSString *jbPath in jailbreakPaths) {
        if ([path hasPrefix:jbPath]) return NO;
    }
    return [self jisign_fileExistsAtPath:path]; // 调用原始方法
}
@end

#pragma mark - NSURLSession Hook (移除版本更新检测)

// 使用 NSURLProtocol 拦截版本检查请求
@interface JiSignURLProtocol : NSURLProtocol
@end
@implementation JiSignURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!gBlockUpdateCheck) return NO;
    NSString *url = request.URL.absoluteString.lowercaseString;
    // 拦截常见的版本更新检测 URL 模式
    if ([url containsString:@"update"] && [url containsString:@"version"]) return YES;
    if ([url containsString:@"checkversion"]) return YES;
    if ([url containsString:@"appupdate"]) return YES;
    if ([url containsString:@"upgrade"]) return YES;
    if ([url containsString:@"itunes.apple.com/lookup"]) return YES;
    return NO;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    // 返回空响应
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Content-Type": @"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSData *empty = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    [self.client URLProtocol:self didLoadData:empty];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

#pragma mark - Init

__attribute__((constructor))
static void JiSignTweaksInit(void) {
    @autoreleasepool {
        // 读取配置
        NSString *configPath = [[NSBundle mainBundle] pathForResource:@"JiSignConfig" ofType:@"plist"];
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];

        gBlockUpdateCheck = [config[@"blockUpdateCheck"] boolValue];
        gBlockClipboard = [config[@"blockClipboard"] boolValue];
        gBlockJailbreak = [config[@"blockJailbreak"] boolValue];
        gBlockAppJump = [config[@"blockAppJump"] boolValue];

        if (gBlockClipboard) {
            swizzle([UIPasteboard class], @selector(string), @selector(jisign_string));
            swizzle([UIPasteboard class], @selector(hasStrings), @selector(jisign_hasStrings));
            swizzle([UIPasteboard class], @selector(hasURLs), @selector(jisign_hasURLs));
        }

        if (gBlockAppJump) {
            swizzle([UIApplication class], @selector(canOpenURL:), @selector(jisign_canOpenURL:));
        }

        if (gBlockJailbreak) {
            swizzle([NSFileManager class], @selector(fileExistsAtPath:), @selector(jisign_fileExistsAtPath:));
        }

        if (gBlockUpdateCheck) {
            [NSURLProtocol registerClass:[JiSignURLProtocol class]];
        }
    }
}
