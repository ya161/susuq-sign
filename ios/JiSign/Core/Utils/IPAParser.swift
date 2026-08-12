import Foundation
import UIKit
import Compression
import ZipArchive

// MARK: - IPA 解析信息模型

/// IPA 文件的解析结果
struct IPAInfo {
    /// App 显示名称
    let displayName: String
    /// Bundle 标识符
    let bundleIdentifier: String
    /// 版本号（如 1.0.0）
    let shortVersion: String
    /// 构建号（如 100）
    let buildVersion: String
    /// 最低支持的 iOS 版本
    let minimumOSVersion: String
    /// App 图标（从 AppIcon 提取）
    let icon: UIImage?
    /// IPA 文件大小（字节）
    let fileSize: Int64
    /// IPA 文件路径
    let filePath: URL
}

// MARK: - IPA 解析错误

enum IPAParserError: LocalizedError {
    case fileNotFound
    case unzipFailed(String)
    case payloadNotFound
    case appBundleNotFound
    case infoPlistNotFound
    case infoPlistReadFailed
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "IPA 文件不存在"
        case .unzipFailed(let reason):
            return "解压 IPA 失败: \(reason)"
        case .payloadNotFound:
            return "未找到 Payload 目录"
        case .appBundleNotFound:
            return "未找到 .app 包"
        case .infoPlistNotFound:
            return "未找到 Info.plist"
        case .infoPlistReadFailed:
            return "读取 Info.plist 失败"
        case .missingRequiredField(let field):
            return "缺少必要字段: \(field)"
        }
    }
}

// MARK: - IPA 解析器

/// IPA 文件解析器
/// 解压 IPA（zip 格式），读取 Info.plist，提取 App 信息和图标
class IPAParser {
    static let shared = IPAParser()

    /// 临时解压目录
    private let tempBaseDir: URL

    private init() {
        tempBaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPAParser", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempBaseDir, withIntermediateDirectories: true)
    }

    // MARK: - 公开方法

    /// 解析 IPA 文件，提取完整信息
    /// - Parameter ipaURL: IPA 文件路径
    /// - Returns: 解析后的 IPAInfo
    func parse(ipaURL: URL) throws -> IPAInfo {
        // 验证文件存在
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw IPAParserError.fileNotFound
        }

        // 获取文件大小
        let fileSize = try getFileSize(at: ipaURL)

        // 解压到临时目录
        let extractDir = try unzipIPA(at: ipaURL)

        defer {
            // 清理临时目录
            try? FileManager.default.removeItem(at: extractDir)
        }

        // 定位 .app 包
        let appBundleURL = try findAppBundle(in: extractDir)

        // 读取 Info.plist
        let infoPlist = try readInfoPlist(in: appBundleURL)

        // 提取 App 图标
        let icon = extractAppIcon(from: appBundleURL, infoPlist: infoPlist)

        // 构建 IPAInfo
        let displayName = (infoPlist["CFBundleDisplayName"] as? String)
            ?? (infoPlist["CFBundleName"] as? String)
            ?? "未知应用"

        guard let bundleIdentifier = infoPlist["CFBundleIdentifier"] as? String else {
            throw IPAParserError.missingRequiredField("CFBundleIdentifier")
        }

        let shortVersion = (infoPlist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let buildVersion = (infoPlist["CFBundleVersion"] as? String) ?? "1"
        let minimumOS = (infoPlist["MinimumOSVersion"] as? String) ?? "未知"

        return IPAInfo(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            minimumOSVersion: minimumOS,
            icon: icon,
            fileSize: fileSize,
            filePath: ipaURL
        )
    }

    // MARK: - 私有方法

    /// 获取文件大小（字节）
    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? Int64) ?? 0
    }

    /// 解压 IPA 文件到临时目录（使用 SSZipArchive / minizip）
    private func unzipIPA(at ipaURL: URL) throws -> URL {
        let extractDir = tempBaseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        var error: NSError?
        let success = SSZipArchive.unzipFile(
            atPath: ipaURL.path,
            toDestination: extractDir.path,
            preserveAttributes: true,
            overwrite: true,
            password: nil,
            error: &error,
            delegate: nil
        )

        if !success {
            throw IPAParserError.unzipFailed(error?.localizedDescription ?? "未知错误")
        }

        return extractDir
    }

    /// 在解压目录中找到 .app 包
    /// 1. 先找标准路径 Payload/*.app
    /// 2. 找不到时递归搜索所有 *.app 目录（兼容非标准 IPA 结构）
    private func findAppBundle(in extractDir: URL) throws -> URL {
        let fm = FileManager.default

        // 标准路径：Payload/*.app
        let payloadDir = extractDir.appendingPathComponent("Payload", isDirectory: true)
        if fm.fileExists(atPath: payloadDir.path) {
            if let contents = try? fm.contentsOfDirectory(
                at: payloadDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ), let appBundle = contents.first(where: { $0.pathExtension == "app" }) {
                return appBundle
            }
        }

        // 备用方案：递归搜索整个解压目录中的 *.app
        if let enumerator = fm.enumerator(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "app" {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                        return fileURL
                    }
                }
            }
        }

        throw IPAParserError.appBundleNotFound
    }

    /// 读取 Info.plist 并解析为字典
    private func readInfoPlist(in appBundleURL: URL) throws -> [String: Any] {
        let plistURL = appBundleURL.appendingPathComponent("Info.plist")

        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw IPAParserError.infoPlistNotFound
        }

        let plistData = try Data(contentsOf: plistURL)

        guard let plist = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw IPAParserError.infoPlistReadFailed
        }

        return plist
    }

    /// 从 .app 包中提取 App 图标
    private func extractAppIcon(from appBundleURL: URL, infoPlist: [String: Any]) -> UIImage? {
        // 尝试从 Info.plist 的 CFBundleIcons 获取图标文件名
        if let icons = infoPlist["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] {

            // 优先使用最大的图标（通常最后一个是最大的）
            for iconName in iconFiles.reversed() {
                // 尝试多种可能的文件名格式
                let candidates = [
                    "\(iconName)@3x.png",
                    "\(iconName)@2x.png",
                    "\(iconName).png",
                    iconName
                ]

                for candidate in candidates {
                    let iconPath = appBundleURL.appendingPathComponent(candidate)
                    if let image = UIImage(contentsOfFile: iconPath.path) {
                        return image
                    }
                }
            }
        }

        // 备用方案：直接搜索常见的图标文件名
        let commonIconNames = [
            "AppIcon60x60@3x.png",
            "AppIcon60x60@2x.png",
            "AppIcon76x76@2x.png",
            "AppIcon-60@3x.png",
            "AppIcon-60@2x.png",
            "Icon-60@3x.png",
            "Icon-60@2x.png",
            "AppIcon.png"
        ]

        for name in commonIconNames {
            let iconPath = appBundleURL.appendingPathComponent(name)
            if let image = UIImage(contentsOfFile: iconPath.path) {
                return image
            }
        }

        return nil
    }

    // MARK: - 工具方法

    /// 清理所有临时文件
    func cleanupTemp() {
        try? FileManager.default.removeItem(at: tempBaseDir)
        try? FileManager.default.createDirectory(at: tempBaseDir, withIntermediateDirectories: true)
    }

    /// 格式化文件大小为可读字符串
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
