#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本地安装器 — 使用 LSApplicationWorkspace 私有 API
@interface LocalInstaller : NSObject

/// 安装 .app 目录到设备（和轻松签/TrollStore 相同方案）
+ (BOOL)installAppAtPath:(NSString *)appPath error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
