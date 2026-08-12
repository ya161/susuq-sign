import Foundation
import UIKit

// MARK: - 存储的 IPA 文件信息

/// 本地存储的 IPA 文件记录
struct StoredIPA: Identifiable {
    let id: String          // 唯一标识（UUID）
    let fileName: String    // 原始文件名
    let filePath: URL       // 沙盒内文件路径
    let importDate: Date    // 导入时间
    let fileSize: Int64     // 文件大小（字节）
    var info: IPAInfo?      // 解析后的详细信息（惰性加载）

    /// 格式化的文件大小
    var formattedSize: String {
        IPAParser.formatFileSize(fileSize)
    }

    /// 格式化的导入时间
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: importDate)
    }
}

// MARK: - IPA 存储错误

enum IPAStorageError: LocalizedError {
    case fileNotFound
    case copyFailed(String)
    case directoryCreateFailed
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "IPA 文件不存在"
        case .copyFailed(let reason):
            return "复制 IPA 失败: \(reason)"
        case .directoryCreateFailed:
            return "创建存储目录失败"
        case .alreadyExists(let name):
            return "同名文件已存在: \(name)"
        }
    }
}

// MARK: - IPA 本地存储管理器

/// IPA 文件本地存储管理
/// 管理 Documents/IPAFiles/ 目录下的所有 IPA 文件
class IPAStorage {
    static let shared = IPAStorage()

    /// IPA 文件存储目录
    private let ipaDir: URL

    /// IPA 解析器
    private let parser = IPAParser.shared

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        ipaDir = docs.appendingPathComponent("IPAFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: ipaDir, withIntermediateDirectories: true)
    }

    // MARK: - 导入 IPA

    /// 从外部 URL 导入 IPA 到沙盒
    /// 支持来自文件选择器、AirDrop、其他 App 分享的 IPA 文件
    /// - Parameters:
    ///   - sourceURL: 外部 IPA 文件路径
    ///   - overwrite: 如果同名文件已存在，是否覆盖
    /// - Returns: 导入后的 StoredIPA 信息
    @discardableResult
    func importIPA(from sourceURL: URL, overwrite: Bool = false) throws -> StoredIPA {
        let fm = FileManager.default

        // 获取安全访问权限（处理来自文件选择器的 URL）
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fm.fileExists(atPath: sourceURL.path) else {
            throw IPAStorageError.fileNotFound
        }

        // 生成唯一 ID 和目标路径
        let id = UUID().uuidString
        let originalName = sourceURL.lastPathComponent
        let destDir = ipaDir.appendingPathComponent(id, isDirectory: true)
        let destPath = destDir.appendingPathComponent(originalName)

        // 创建子目录
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // 复制文件
        do {
            try fm.copyItem(at: sourceURL, to: destPath)
        } catch {
            // 清理失败的目录
            try? fm.removeItem(at: destDir)
            throw IPAStorageError.copyFailed(error.localizedDescription)
        }

        // 获取文件属性
        let attributes = try fm.attributesOfItem(atPath: destPath.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0

        // 只保存基础元数据，不解析 IPA（避免大文件导入时 UI 卡顿）
        let metadata: [String: Any] = [
            "id": id,
            "fileName": originalName,
            "importDate": Date().timeIntervalSince1970,
            "fileSize": fileSize
        ]
        let metadataPath = destDir.appendingPathComponent("metadata.plist")
        let metadataData = try PropertyListSerialization.data(
            fromPropertyList: metadata, format: .xml, options: 0
        )
        try metadataData.write(to: metadataPath)

        return StoredIPA(
            id: id,
            fileName: originalName,
            filePath: destPath,
            importDate: Date(),
            fileSize: fileSize,
            info: nil
        )
    }

    // MARK: - 列出所有 IPA

    /// 获取所有已导入的 IPA 文件列表
    /// - Returns: StoredIPA 数组，按导入时间倒序排列
    func listIPAs() -> [StoredIPA] {
        let fm = FileManager.default

        guard let dirs = try? fm.contentsOfDirectory(
            at: ipaDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var ipas: [StoredIPA] = []

        for dir in dirs {
            // 读取元数据
            let metadataPath = dir.appendingPathComponent("metadata.plist")
            guard let metadataData = try? Data(contentsOf: metadataPath),
                  let metadata = try? PropertyListSerialization.propertyList(
                      from: metadataData,
                      options: [],
                      format: nil
                  ) as? [String: Any],
                  let id = metadata["id"] as? String,
                  let fileName = metadata["fileName"] as? String,
                  let importTimestamp = metadata["importDate"] as? TimeInterval,
                  let fileSize = metadata["fileSize"] as? Int64 else {
                continue
            }

            let filePath = dir.appendingPathComponent(fileName)

            // 确保 IPA 文件依然存在
            guard fm.fileExists(atPath: filePath.path) else {
                // 文件丢失，清理元数据
                try? fm.removeItem(at: dir)
                continue
            }

            // 从缓存读取 App 信息（不做同步解析，未解析的由 UI 层异步处理）
            let cachedDisplayName = metadata["displayName"] as? String
            let cachedBundleID = metadata["bundleIdentifier"] as? String
            let cachedVersion = metadata["shortVersion"] as? String
            let cachedBuild = metadata["buildVersion"] as? String
            let iconPath = dir.appendingPathComponent("icon.png")
            let cachedIcon = UIImage(contentsOfFile: iconPath.path)

            let info: IPAInfo? = cachedBundleID != nil ? IPAInfo(
                displayName: cachedDisplayName ?? fileName,
                bundleIdentifier: cachedBundleID!,
                shortVersion: cachedVersion ?? "1.0",
                buildVersion: cachedBuild ?? "1",
                minimumOSVersion: "",
                icon: cachedIcon,
                fileSize: fileSize,
                filePath: filePath
            ) : nil

            let ipa = StoredIPA(
                id: id,
                fileName: fileName,
                filePath: filePath,
                importDate: Date(timeIntervalSince1970: importTimestamp),
                fileSize: fileSize,
                info: info
            )
            ipas.append(ipa)
        }

        // 按导入时间倒序排列（最新的在前）
        return ipas.sorted { $0.importDate > $1.importDate }
    }

    // MARK: - 删除 IPA

    /// 删除指定的 IPA 文件
    /// - Parameter id: IPA 的唯一标识
    func deleteIPA(id: String) throws {
        let ipaDir = ipaDir.appendingPathComponent(id, isDirectory: true)

        guard FileManager.default.fileExists(atPath: ipaDir.path) else {
            throw IPAStorageError.fileNotFound
        }

        try FileManager.default.removeItem(at: ipaDir)
    }

    /// 批量删除 IPA 文件
    /// - Parameter ids: 要删除的 IPA ID 列表
    func deleteIPAs(ids: [String]) throws {
        for id in ids {
            try deleteIPA(id: id)
        }
    }

    // MARK: - 获取详细信息

    /// 获取 IPA 的详细解析信息
    /// 首次调用时会解析 IPA，结果不缓存（因为 IPAInfo 包含 UIImage）
    /// - Parameter id: IPA 的唯一标识
    /// - Returns: 包含完整解析信息的 StoredIPA
    func getIPADetail(id: String) throws -> StoredIPA {
        let fm = FileManager.default
        let dir = ipaDir.appendingPathComponent(id, isDirectory: true)

        // 读取元数据
        let metadataPath = dir.appendingPathComponent("metadata.plist")
        guard let metadataData = try? Data(contentsOf: metadataPath),
              let metadata = try? PropertyListSerialization.propertyList(
                  from: metadataData,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let fileName = metadata["fileName"] as? String else {
            throw IPAStorageError.fileNotFound
        }

        let filePath = dir.appendingPathComponent(fileName)

        guard fm.fileExists(atPath: filePath.path) else {
            throw IPAStorageError.fileNotFound
        }

        let importTimestamp = (metadata["importDate"] as? TimeInterval) ?? 0
        let fileSize = (metadata["fileSize"] as? Int64) ?? 0

        // 调用 IPAParser 解析详细信息
        let info = try parser.parse(ipaURL: filePath)

        return StoredIPA(
            id: id,
            fileName: fileName,
            filePath: filePath,
            importDate: Date(timeIntervalSince1970: importTimestamp),
            fileSize: fileSize,
            info: info
        )
    }

    // MARK: - 更新缓存

    /// 将解析结果写入 metadata 缓存和图标文件
    /// - Parameters:
    ///   - id: IPA 唯一标识
    ///   - info: 解析得到的 IPAInfo
    func updateIPACache(id: String, info: IPAInfo) {
        let dir = ipaDir.appendingPathComponent(id, isDirectory: true)
        let metadataPath = dir.appendingPathComponent("metadata.plist")

        guard let metadataData = try? Data(contentsOf: metadataPath),
              var metadata = try? PropertyListSerialization.propertyList(
                  from: metadataData, options: .mutableContainersAndLeaves, format: nil
              ) as? [String: Any] else {
            return
        }

        metadata["displayName"] = info.displayName
        metadata["bundleIdentifier"] = info.bundleIdentifier
        metadata["shortVersion"] = info.shortVersion
        metadata["buildVersion"] = info.buildVersion

        if let iconData = info.icon?.pngData() {
            let iconPath = dir.appendingPathComponent("icon.png")
            try? iconData.write(to: iconPath)
        }

        if let data = try? PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0) {
            try? data.write(to: metadataPath)
        }
    }

    // MARK: - 工具方法

    /// 获取存储目录总大小
    func totalStorageSize() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: ipaDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    /// 清空所有 IPA 文件
    func clearAll() throws {
        let fm = FileManager.default
        try fm.removeItem(at: ipaDir)
        try fm.createDirectory(at: ipaDir, withIntermediateDirectories: true)
    }

    /// 获取存储目录路径（用于调试）
    var storageDirectory: URL {
        return ipaDir
    }
}
