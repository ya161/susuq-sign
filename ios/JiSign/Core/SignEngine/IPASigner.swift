import Foundation
import UIKit
import ZSign
import ZipArchive

/// IPA 签名引擎
/// zsign-ios 简化版只接受 .app 文件夹路径，流程：解压 IPA → zsign .app → 重新打包 IPA
class IPASigner {
    static let shared = IPASigner()

    private let outputDir: URL
    private let tempDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        outputDir = docs.appendingPathComponent("SignedIPAs", isDirectory: true)
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("IPASigner", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    struct SignOptions {
        let ipaPath: URL
        let p12Path: URL
        let mobileprovisionPath: URL
        let p12Password: String
        var newBundleID: String?
        var newAppName: String?
        var customIcon: UIImage?  // 自定义图标
        // 高级选项 — Info.plist / 文件系统修改
        var removeVersionLimit: Bool = false
        var removeDeviceLimit: Bool = false
        var enableFileSharing: Bool = false
        var removeURLSchemes: Bool = false
        var removeExtensions: Bool = false
        // 高级选项 — Dylib Hook
        var removeUpdateCheck: Bool = false
        var removeClipboard: Bool = false
        var removeJailbreakDetection: Bool = false
        var removeAppJumpDetection: Bool = false
    }

    struct SignResult {
        let signedIPAPath: URL
        let appName: String
        let bundleID: String
    }

    func sign(options: SignOptions, progress: @escaping (Double, String) -> Void) async throws -> SignResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let result = try performSign(options: options, progress: progress)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performSign(options: SignOptions, progress: @escaping (Double, String) -> Void) throws -> SignResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: options.ipaPath.path) else { throw SignError.ipaNotFound }
        guard fm.fileExists(atPath: options.p12Path.path) else { throw SignError.certNotFound }
        guard fm.fileExists(atPath: options.mobileprovisionPath.path) else { throw SignError.certNotFound }

        let workID = UUID().uuidString
        let workDir = tempDir.appendingPathComponent("work_\(workID)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        // 1. 解压 IPA
        DispatchQueue.main.async { progress(0.05, "读取 IPA 应用包...") }
        let unzipDir = workDir.appendingPathComponent("unzipped", isDirectory: true)
        try fm.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        var unzipError: NSError?
        guard SSZipArchive.unzipFile(atPath: options.ipaPath.path, toDestination: unzipDir.path, preserveAttributes: true, overwrite: true, password: nil, error: &unzipError, delegate: nil) else {
            throw SignError.signFailed("IPA 解压失败: \(unzipError?.localizedDescription ?? "")")
        }

        // 2. 找到 Payload/*.app（递归搜索，兼容不同 IPA 结构）
        let appDir: URL = try {
            // 先检查标准结构：unzipDir/Payload/*.app
            let standardPayload = unzipDir.appendingPathComponent("Payload", isDirectory: true)
            if fm.fileExists(atPath: standardPayload.path) {
                if let contents = try? fm.contentsOfDirectory(at: standardPayload, includingPropertiesForKeys: nil),
                   let app = contents.first(where: { $0.pathExtension == "app" }) {
                    return app
                }
            }

            // 搜索所有子目录中的 Payload/*.app
            if let topItems = try? fm.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil) {
                for item in topItems {
                    let nested = item.appendingPathComponent("Payload", isDirectory: true)
                    if fm.fileExists(atPath: nested.path),
                       let contents = try? fm.contentsOfDirectory(at: nested, includingPropertiesForKeys: nil),
                       let app = contents.first(where: { $0.pathExtension == "app" }) {
                        return app
                    }
                }

                // 直接搜索 .app 目录
                for item in topItems {
                    if item.pathExtension == "app" {
                        return item
                    }
                }
            }

            // 调试：列出实际提取的内容
            let extracted = (try? fm.contentsOfDirectory(atPath: unzipDir.path)) ?? []
            throw SignError.signFailed("IPA 结构异常，提取内容: \(extracted.prefix(10).joined(separator: ", "))")
        }()

        DispatchQueue.main.async { progress(0.1, "解析应用: \(appDir.lastPathComponent)") }

        // 2.5 替换自定义图标
        if let customIcon = options.customIcon {
            let iconResult = replaceAppIcon(in: appDir, with: customIcon)
            DispatchQueue.main.async { progress(0.15, "图标替换: \(iconResult)") }
        }

        // 2.6 应用高级选项
        let advResult = applyAdvancedOptions(appDir: appDir, options: options)
        if !advResult.isEmpty {
            DispatchQueue.main.async { progress(0.2, advResult) }
        }

        // 2.7 注入 Hook Dylib
        let needsHook = options.removeUpdateCheck || options.removeClipboard ||
                        options.removeJailbreakDetection || options.removeAppJumpDetection
        if needsHook {
            let hookResult = injectTweaksDylib(appDir: appDir, options: options)
            DispatchQueue.main.async { progress(0.25, hookResult) }
        }

        // 3. 调用 zsign 签名
        DispatchQueue.main.async { progress(0.3, "正在签名...") }
        let ret = zsign(
            appDir.path,
            options.p12Path.path,
            options.mobileprovisionPath.path,
            options.p12Password,
            options.newBundleID ?? "",
            options.newAppName ?? ""
        )

        guard ret == 0 else {
            throw SignError.signFailed("zsign 错误码: \(ret)")
        }
        DispatchQueue.main.async { progress(0.6, "代码签名完成") }

        // 4. 重新打包为 IPA（使用 SSZipArchive / minizip，保留权限和符号链接）
        DispatchQueue.main.async { progress(0.7, "打包签名结果...") }
        let originalName = options.ipaPath.deletingPathExtension().lastPathComponent
        let suffix: String
        if let bid = options.newBundleID, !bid.isEmpty {
            // 用 bundle ID 的最后一段做唯一后缀（如 clone12）
            let tag = bid.components(separatedBy: ".").last ?? "clone"
            suffix = "_\(tag)"
        } else {
            suffix = "_signed"
        }
        let outputFileName = "\(originalName)\(suffix).ipa"
        let outputPath = outputDir.appendingPathComponent(outputFileName)
        try? fm.removeItem(at: outputPath)

        // 直接从解压目录打包（不 copyItem，避免破坏符号链接）
        guard SSZipArchive.createZipFile(atPath: outputPath.path, withContentsOfDirectory: unzipDir.path, keepParentDirectory: false) else {
            throw SignError.signFailed("IPA 打包失败")
        }

        DispatchQueue.main.async { progress(1.0, "签名完成！") }

        return SignResult(
            signedIPAPath: outputPath,
            appName: options.newAppName ?? originalName,
            bundleID: options.newBundleID ?? ""
        )
    }

    /// 批量签名（多开模式）— 解压一次 IPA，签名多个不同 bundle ID 的克隆
    func signBatch(ipaPath: URL, p12Path: URL, mobileprovisionPath: URL, p12Password: String,
                   clones: [(bundleID: String, appName: String)],
                   progress: @escaping (Double, String) -> Void) async throws -> [SignResult] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let results = try performBatchSign(
                        ipaPath: ipaPath, p12Path: p12Path, mobileprovisionPath: mobileprovisionPath,
                        p12Password: p12Password, clones: clones, progress: progress
                    )
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performBatchSign(ipaPath: URL, p12Path: URL, mobileprovisionPath: URL,
                                  p12Password: String, clones: [(bundleID: String, appName: String)],
                                  progress: @escaping (Double, String) -> Void) throws -> [SignResult] {
        let fm = FileManager.default
        let workID = UUID().uuidString
        let workDir = tempDir.appendingPathComponent("batch_\(workID)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        var results: [SignResult] = []
        let total = clones.count

        for (i, clone) in clones.enumerated() {
            let pct = 0.1 + (Double(i) / Double(total)) * 0.8
            DispatchQueue.main.async { progress(pct, "签名 \(i + 1)/\(total)...") }

            // 每个克隆独立解压（SSZipArchive 保留符号链接和权限，copyItem 会破坏）
            let cloneDir = workDir.appendingPathComponent("clone_\(i)", isDirectory: true)
            try fm.createDirectory(at: cloneDir, withIntermediateDirectories: true)
            var unzipError: NSError?
            guard SSZipArchive.unzipFile(atPath: ipaPath.path, toDestination: cloneDir.path,
                                         preserveAttributes: true, overwrite: true, password: nil,
                                         error: &unzipError, delegate: nil) else {
                throw SignError.signFailed("克隆 \(i + 1) 解压失败")
            }

            // 找到 .app
            let clonePayload = cloneDir.appendingPathComponent("Payload")
            guard let cloneAppDirs = try? fm.contentsOfDirectory(at: clonePayload, includingPropertiesForKeys: nil),
                  let cloneAppDir = cloneAppDirs.first(where: { $0.pathExtension == "app" }) else {
                throw SignError.signFailed("克隆 \(i + 1) 找不到 .app")
            }

            // zsign 签名
            let ret = zsign(
                cloneAppDir.path, p12Path.path,
                mobileprovisionPath.path, p12Password,
                clone.bundleID, clone.appName
            )
            guard ret == 0 else {
                throw SignError.signFailed("克隆 \(i + 1) 签名失败")
            }

            // 打包为 IPA
            let originalName = ipaPath.deletingPathExtension().lastPathComponent
            let outputFileName = "\(originalName)_clone\(i + 1).ipa"
            let outputPath = outputDir.appendingPathComponent(outputFileName)
            try? fm.removeItem(at: outputPath)
            guard SSZipArchive.createZipFile(atPath: outputPath.path,
                                             withContentsOfDirectory: cloneDir.path,
                                             keepParentDirectory: false) else {
                throw SignError.signFailed("克隆 \(i + 1) 打包失败")
            }

            // 清理此克隆的解压目录（释放空间）
            try? fm.removeItem(at: cloneDir)

            results.append(SignResult(
                signedIPAPath: outputPath,
                appName: clone.appName,
                bundleID: clone.bundleID
            ))
        }

        DispatchQueue.main.async { progress(1.0, "签名完成！") }
        return results
    }

    // MARK: - 高级选项：Info.plist / 文件系统修改

    /// 在 zsign 签名前应用高级选项，返回操作结果描述
    @discardableResult
    private func applyAdvancedOptions(appDir: URL, options: SignOptions) -> String {
        var results: [String] = []
        let fm = FileManager.default
        let plistPath = appDir.appendingPathComponent("Info.plist")

        // 只在需要修改 Info.plist 时才读取
        let needsPlistMod = options.removeVersionLimit || options.removeDeviceLimit ||
                            options.enableFileSharing || options.removeURLSchemes
        if needsPlistMod {
            guard let plistData = try? Data(contentsOf: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: plistData,
                      options: .mutableContainersAndLeaves,
                      format: nil
                  ) as? NSMutableDictionary else {
                results.append("❌ Info.plist 读取失败")
                return results.joined(separator: ", ")
            }

            if options.removeVersionLimit {
                plist["MinimumOSVersion"] = "9.0"
                results.append("✓ 版本限制")
            }
            if options.removeDeviceLimit {
                plist["UIDeviceFamily"] = [1, 2]
                plist.removeObject(forKey: "UISupportedDevices")
                results.append("✓ 设备限制")
            }
            if options.enableFileSharing {
                plist["UIFileSharingEnabled"] = true
                plist["LSSupportsOpeningDocumentsInPlace"] = true
                results.append("✓ 文件共享")
            }
            if options.removeURLSchemes {
                plist.removeObject(forKey: "CFBundleURLTypes")
                plist.removeObject(forKey: "LSApplicationQueriesSchemes")
                results.append("✓ URL Schemes")
            }

            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                try? data.write(to: plistPath)
            } else {
                results.append("❌ Info.plist 写入失败")
            }
        }

        if options.removeExtensions {
            let pluginsDir = appDir.appendingPathComponent("PlugIns")
            let watchDir = appDir.appendingPathComponent("Watch")
            let p = fm.fileExists(atPath: pluginsDir.path)
            let w = fm.fileExists(atPath: watchDir.path)
            try? fm.removeItem(at: pluginsDir)
            try? fm.removeItem(at: watchDir)
            results.append("✓ 扩展(PlugIns:\(p ? "删除" : "无"),Watch:\(w ? "删除" : "无"))")
        }

        return results.isEmpty ? "" : "高级: " + results.joined(separator: " ")
    }

    // MARK: - 高级选项：Dylib Hook 注入

    /// 将 JiSignTweaks.dylib 注入到 .app 中，返回结果
    @discardableResult
    private func injectTweaksDylib(appDir: URL, options: SignOptions) -> String {
        let fm = FileManager.default

        let frameworksDir = appDir.appendingPathComponent("Frameworks")
        try? fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)

        guard let dylibSource = Bundle.main.url(forResource: "JiSignTweaks", withExtension: "dylib") else {
            return "❌ JiSignTweaks.dylib 未找到"
        }
        let dylibDest = frameworksDir.appendingPathComponent("JiSignTweaks.dylib")
        try? fm.removeItem(at: dylibDest) // 移除已有的
        try? fm.copyItem(at: dylibSource, to: dylibDest)

        // 3. 创建 JiSignConfig.plist 控制哪些 Hook 生效
        let config: [String: Any] = [
            "blockUpdateCheck": options.removeUpdateCheck,
            "blockClipboard": options.removeClipboard,
            "blockJailbreak": options.removeJailbreakDetection,
            "blockAppJump": options.removeAppJumpDetection
        ]
        let configPath = appDir.appendingPathComponent("JiSignConfig.plist")
        if let configData = try? PropertyListSerialization.data(
            fromPropertyList: config, format: .binary, options: 0
        ) {
            try? configData.write(to: configPath)
        }

        // 4. 注入 load command 到主二进制
        let plistPath = appDir.appendingPathComponent("Info.plist")
        if let plistData = try? Data(contentsOf: plistPath),
           let plist = try? PropertyListSerialization.propertyList(
               from: plistData, options: [], format: nil
           ) as? [String: Any],
           let executable = plist["CFBundleExecutable"] as? String {
            let execPath = appDir.appendingPathComponent(executable)
            let loadPath = "@executable_path/Frameworks/JiSignTweaks.dylib"
            do {
                try DylibInjector.shared.addLoadCommand(
                    executableURL: execPath,
                    dylibPath: loadPath,
                    weakLink: false
                )
                return "Hook注入: ✓ dylib复制 ✓ config ✓ load command (\(executable))"
            } catch {
                return "Hook注入: ✓ dylib复制 ✓ config ❌ load command: \(error.localizedDescription)"
            }
        }
        return "Hook注入: ❌ 找不到主二进制"
    }

    /// 替换 .app 内的所有图标文件，返回结果
    @discardableResult
    private func replaceAppIcon(in appDir: URL, with icon: UIImage) -> String {
        let fm = FileManager.default

        // 读取 Info.plist 获取图标文件名
        let plistPath = appDir.appendingPathComponent("Info.plist")
        // 生成所有尺寸的图标 PNG 文件
        let iconSizes: [(name: String, size: CGFloat, scale: CGFloat)] = [
            ("JiSignIcon60x60@2x.png", 60, 2),   // 120x120 iPhone
            ("JiSignIcon60x60@3x.png", 60, 3),   // 180x180 iPhone
            ("JiSignIcon76x76@2x.png", 76, 2),   // 152x152 iPad
            ("JiSignIcon83.5x83.5@2x.png", 83.5, 2), // 167x167 iPad Pro
            ("JiSignIcon40x40@2x.png", 40, 2),   // 80x80 Spotlight
            ("JiSignIcon40x40@3x.png", 40, 3),   // 120x120 Spotlight
            ("JiSignIcon29x29@2x.png", 29, 2),   // 58x58 Settings
            ("JiSignIcon29x29@3x.png", 29, 3),   // 87x87 Settings
            ("JiSignIcon20x20@2x.png", 20, 2),   // 40x40 Notification
            ("JiSignIcon20x20@3x.png", 20, 3),   // 60x60 Notification
        ]

        var created = 0
        for iconSpec in iconSizes {
            let pixelSize = iconSpec.size * iconSpec.scale
            let size = CGSize(width: pixelSize, height: pixelSize)
            UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
            icon.draw(in: CGRect(origin: .zero, size: size))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            if let pngData = resized?.pngData() {
                let filePath = appDir.appendingPathComponent(iconSpec.name)
                try? pngData.write(to: filePath)
                created += 1
            }
        }

        // 修改 Info.plist 引用自定义图标文件（覆盖 Assets.car 中的图标）
        guard let plistData = try? Data(contentsOf: plistPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: plistData, options: .mutableContainersAndLeaves, format: nil
              ) as? NSMutableDictionary else {
            return "✓ 生成\(created)个图标 ❌ Info.plist读取失败"
        }

        // 设置 CFBundleIcons 指向自定义图标
        let primaryIcon: NSMutableDictionary = [
            "CFBundleIconFiles": ["JiSignIcon60x60", "JiSignIcon76x76", "JiSignIcon83.5x83.5",
                                  "JiSignIcon40x40", "JiSignIcon29x29", "JiSignIcon20x20"],
            "CFBundleIconName": "JiSignIcon"
        ]
        let bundleIcons: NSMutableDictionary = ["CFBundlePrimaryIcon": primaryIcon]
        plist["CFBundleIcons"] = bundleIcons
        plist["CFBundleIcons~ipad"] = bundleIcons

        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? data.write(to: plistPath)
        }

        // 同时替换已有的 PNG 图标文件（如果有的话）
        if let contents = try? fm.contentsOfDirectory(atPath: appDir.path) {
            for fileName in contents where fileName.hasSuffix(".png") {
                if fileName.hasPrefix("AppIcon") || fileName.hasPrefix("Icon-") || fileName.hasPrefix("Icon@") {
                    let filePath = appDir.appendingPathComponent(fileName)
                    if let original = UIImage(contentsOfFile: filePath.path) {
                        let size = CGSize(width: original.size.width * original.scale, height: original.size.height * original.scale)
                        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                        icon.draw(in: CGRect(origin: .zero, size: size))
                        let resized = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        if let pngData = resized?.pngData() {
                            try? pngData.write(to: filePath)
                            created += 1
                        }
                    }
                }
            }
        }

        return "✓ 生成\(created)个图标+修改Info.plist引用"
    }

    func cleanupTemp() {
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func listSignedIPAs() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "ipa" }
    }
}

enum SignError: LocalizedError {
    case ipaNotFound
    case certNotFound
    case signFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .ipaNotFound: return "IPA 文件不存在"
        case .certNotFound: return "证书文件不存在"
        case .signFailed(let msg): return "签名失败: \(msg)"
        case .installFailed(let msg): return "安装失败: \(msg)"
        }
    }
}
