#import "LocalInstaller.h"

// LSApplicationWorkspace 私有 API 协议声明
@protocol LSAppWorkspaceProtocol <NSObject>
- (BOOL)installApplication:(NSURL *)url
               withOptions:(NSDictionary *)options
                     error:(NSError **)error;
@end

@implementation LocalInstaller

+ (BOOL)installAppAtPath:(NSString *)appPath error:(NSError **)error {
    // 1. 获取 LSApplicationWorkspace 类
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) {
        if (error) *error = [NSError errorWithDomain:@"JiSign" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"无法加载 LSApplicationWorkspace"}];
        return NO;
    }

    // 2. 获取 defaultWorkspace 实例
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id workspace = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
#pragma clang diagnostic pop

    if (!workspace) {
        if (error) *error = [NSError errorWithDomain:@"JiSign" code:-2
            userInfo:@{NSLocalizedDescriptionKey: @"无法获取安装服务"}];
        return NO;
    }

    // 3. 检查安装方法是否可用
    SEL installSel = NSSelectorFromString(@"installApplication:withOptions:error:");
    if (![workspace respondsToSelector:installSel]) {
        if (error) *error = [NSError errorWithDomain:@"JiSign" code:-3
            userInfo:@{NSLocalizedDescriptionKey: @"当前 iOS 版本不支持本地安装 API"}];
        return NO;
    }

    // 4. 调用安装
    NSURL *appURL = [NSURL fileURLWithPath:appPath];
    NSDictionary *options = @{
        @"PackageType": @"Developer"
    };

    // 使用 protocol cast 调用
    id<LSAppWorkspaceProtocol> ws = (id<LSAppWorkspaceProtocol>)workspace;
    NSError *installError = nil;
    BOOL result = [ws installApplication:appURL withOptions:options error:&installError];

    if (!result && error) {
        if (installError) {
            *error = installError;
        } else {
            *error = [NSError errorWithDomain:@"JiSign" code:-4
                userInfo:@{NSLocalizedDescriptionKey: @"安装失败，请确认证书已信任"}];
        }
    }

    return result;
}

@end
