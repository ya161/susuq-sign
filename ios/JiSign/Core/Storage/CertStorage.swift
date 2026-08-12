import Foundation

/// 证书文件本地存储管理
class CertStorage {
    static let shared = CertStorage()

    private let certsDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        certsDir = docs.appendingPathComponent("Certificates", isDirectory: true)
        try? FileManager.default.createDirectory(at: certsDir, withIntermediateDirectories: true)
    }

    /// 保存证书文件（P12 + mobileprovision）
    func saveCert(batchNo: String, p12Base64: String, mobileprovisionBase64: String) throws -> (p12Path: URL, mpPath: URL) {
        let certDir = certsDir.appendingPathComponent(batchNo, isDirectory: true)
        try FileManager.default.createDirectory(at: certDir, withIntermediateDirectories: true)

        guard let p12Data = Data(base64Encoded: p12Base64) else {
            throw CertStorageError.invalidBase64("P12 数据解码失败")
        }
        guard let mpData = Data(base64Encoded: mobileprovisionBase64) else {
            throw CertStorageError.invalidBase64("mobileprovision 数据解码失败")
        }

        let p12Path = certDir.appendingPathComponent("cert.p12")
        let mpPath = certDir.appendingPathComponent("cert.mobileprovision")

        try p12Data.write(to: p12Path)
        try mpData.write(to: mpPath)

        return (p12Path, mpPath)
    }

    /// 获取所有已保存的证书
    func listCerts() -> [SavedCert] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: certsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents.compactMap { dir -> SavedCert? in
            let batchNo = dir.lastPathComponent
            let p12Path = dir.appendingPathComponent("cert.p12")
            let mpPath = dir.appendingPathComponent("cert.mobileprovision")

            guard FileManager.default.fileExists(atPath: p12Path.path),
                  FileManager.default.fileExists(atPath: mpPath.path) else {
                return nil
            }

            let creationDate = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

            return SavedCert(
                batchNo: batchNo,
                p12Path: p12Path,
                mobileprovisionPath: mpPath,
                createdAt: creationDate
            )
        }
    }

    /// 删除证书
    func deleteCert(batchNo: String) throws {
        let certDir = certsDir.appendingPathComponent(batchNo)
        try FileManager.default.removeItem(at: certDir)
    }

    /// 导入外部证书文件
    func importCert(p12URL: URL, mobileprovisionURL: URL, batchNo: String) throws -> (p12Path: URL, mpPath: URL) {
        let certDir = certsDir.appendingPathComponent(batchNo, isDirectory: true)
        try FileManager.default.createDirectory(at: certDir, withIntermediateDirectories: true)

        let p12Path = certDir.appendingPathComponent("cert.p12")
        let mpPath = certDir.appendingPathComponent("cert.mobileprovision")

        // 处理安全作用域资源（Security-Scoped Resource）
        // fileImporter 返回的 URL 需要先 startAccessingSecurityScopedResource 才能访问
        let p12Accessed = p12URL.startAccessingSecurityScopedResource()
        let mpAccessed = mobileprovisionURL.startAccessingSecurityScopedResource()

        defer {
            if p12Accessed { p12URL.stopAccessingSecurityScopedResource() }
            if mpAccessed { mobileprovisionURL.stopAccessingSecurityScopedResource() }
        }

        do {
            // 先读取数据，确保可以访问
            let p12Data = try Data(contentsOf: p12URL)
            let mpData = try Data(contentsOf: mobileprovisionURL)

            // 写入到目标位置
            try p12Data.write(to: p12Path)
            try mpData.write(to: mpPath)
        } catch {
            // 清理已创建的目录
            try? FileManager.default.removeItem(at: certDir)
            throw error
        }

        return (p12Path, mpPath)
    }
}

struct SavedCert {
    let batchNo: String
    let p12Path: URL
    let mobileprovisionPath: URL
    let createdAt: Date
}

enum CertStorageError: LocalizedError {
    case invalidBase64(String)

    var errorDescription: String? {
        switch self {
        case .invalidBase64(let msg): return msg
        }
    }
}
