import Foundation

// MARK: - Dylib 信息模型

/// 已加载的动态库信息
struct DylibInfo: Identifiable {
    let id: String              // 唯一标识
    let name: String            // 动态库名称（如 libfoo.dylib）
    let path: String            // 在 Mach-O 中记录的加载路径
    let type: DylibType         // 类型：dylib 或 framework
    let isWeakLinked: Bool      // 是否为弱链接

    /// 动态库类型
    enum DylibType: String {
        case dylib = "dylib"
        case framework = "framework"
    }
}

// MARK: - 注入错误

enum DylibInjectorError: LocalizedError {
    case ipaNotFound
    case appBundleNotFound
    case executableNotFound
    case machOParseFailed(String)
    case dylibNotFound(String)
    case injectionFailed(String)
    case removeFailed(String)
    case noAvailableSpace

    var errorDescription: String? {
        switch self {
        case .ipaNotFound:
            return "IPA 文件不存在"
        case .appBundleNotFound:
            return "未找到 .app 包"
        case .executableNotFound:
            return "未找到可执行文件"
        case .machOParseFailed(let reason):
            return "Mach-O 解析失败: \(reason)"
        case .dylibNotFound(let name):
            return "找不到动态库: \(name)"
        case .injectionFailed(let reason):
            return "注入失败: \(reason)"
        case .removeFailed(let reason):
            return "移除失败: \(reason)"
        case .noAvailableSpace:
            return "Mach-O 头部空间不足，无法添加 load command"
        }
    }
}

// MARK: - Mach-O 常量

/// Mach-O 文件格式相关常量
private enum MachO {
    // Magic numbers
    static let magic32: UInt32 = 0xFEEDFACE       // 32 位
    static let magic64: UInt32 = 0xFEEDFACF       // 64 位
    static let fatMagic: UInt32 = 0xCAFEBABE       // FAT（通用二进制）
    static let fatMagicSwapped: UInt32 = 0xBEBAFECA

    // Load command types
    static let lcLoadDylib: UInt32 = 0x0C          // LC_LOAD_DYLIB
    static let lcLoadWeakDylib: UInt32 = 0x80000018 // LC_LOAD_WEAK_DYLIB
    static let lcRpath: UInt32 = 0x8000001C        // LC_RPATH
    static let lcCodeSignature: UInt32 = 0x1D      // LC_CODE_SIGNATURE

    // 头部大小
    static let headerSize64: Int = 32              // mach_header_64 大小
    static let headerSize32: Int = 28              // mach_header 大小
    static let loadCommandHeaderSize: Int = 8      // load command 头部（cmd + cmdsize）

    // Dylib command 结构偏移
    // struct dylib_command {
    //     uint32_t cmd;           // LC_LOAD_DYLIB 等
    //     uint32_t cmdsize;       // 整个命令的大小
    //     struct dylib {
    //         uint32_t name;      // 名称偏移量
    //         uint32_t timestamp;
    //         uint32_t current_version;
    //         uint32_t compatibility_version;
    //     };
    // };
    static let dylibCommandBaseSize: Int = 24      // 不含名称字符串
}

// MARK: - Dylib 注入器

/// Dylib 注入器
/// 解析 Mach-O 二进制，列出/添加/移除 dylib load commands
class DylibInjector {
    static let shared = DylibInjector()

    private init() {}

    // MARK: - 列出已有的 dylib/framework

    /// 列出 IPA 中可执行文件已加载的所有 dylib 和 framework
    /// - Parameter ipaExtractedDir: 已解压的 IPA 目录（包含 Payload/*.app）
    /// - Returns: DylibInfo 数组
    func listDylibs(in ipaExtractedDir: URL) throws -> [DylibInfo] {
        let executableURL = try findExecutable(in: ipaExtractedDir)
        let executableData = try Data(contentsOf: executableURL)

        return try parseDylibs(from: executableData)
    }

    /// 从 Mach-O 数据中解析所有 dylib load commands
    private func parseDylibs(from data: Data) throws -> [DylibInfo] {
        guard data.count >= 4 else {
            throw DylibInjectorError.machOParseFailed("文件太小")
        }

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }

        switch magic {
        case MachO.magic64:
            return try parseDylibsFromMachO(data: data, headerSize: MachO.headerSize64)
        case MachO.magic32:
            return try parseDylibsFromMachO(data: data, headerSize: MachO.headerSize32)
        case MachO.fatMagic, MachO.fatMagicSwapped:
            // FAT 二进制：解析第一个架构
            return try parseDylibsFromFat(data: data)
        default:
            throw DylibInjectorError.machOParseFailed("未知的 Magic: \(String(format: "0x%X", magic))")
        }
    }

    /// 解析单架构 Mach-O 中的 dylib load commands
    private func parseDylibsFromMachO(data: Data, headerSize: Int) throws -> [DylibInfo] {
        guard data.count >= headerSize else {
            throw DylibInjectorError.machOParseFailed("头部不完整")
        }

        // 读取 load commands 的数量和总大小
        // ncmds 在 offset 16, sizeofcmds 在 offset 20
        let ncmds = data.subdata(in: 16..<20)
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        let sizeofcmds = data.subdata(in: 20..<24)
            .withUnsafeBytes { $0.load(as: UInt32.self) }

        guard headerSize + Int(sizeofcmds) <= data.count else {
            throw DylibInjectorError.machOParseFailed("load commands 超出文件范围")
        }

        var dylibs: [DylibInfo] = []
        var offset = headerSize

        for _ in 0..<ncmds {
            guard offset + MachO.loadCommandHeaderSize <= data.count else { break }

            let cmd = data.subdata(in: offset..<(offset + 4))
                .withUnsafeBytes { $0.load(as: UInt32.self) }
            let cmdsize = Int(data.subdata(in: (offset + 4)..<(offset + 8))
                .withUnsafeBytes { $0.load(as: UInt32.self) })

            guard cmdsize > 0, offset + cmdsize <= data.count else { break }

            // 检查是否是 dylib 加载命令
            if cmd == MachO.lcLoadDylib || cmd == MachO.lcLoadWeakDylib {
                // 名称偏移量在 offset + 8（dylib.name.offset）
                let nameOffset = Int(data.subdata(in: (offset + 8)..<(offset + 12))
                    .withUnsafeBytes { $0.load(as: UInt32.self) })

                let nameStart = offset + nameOffset
                let nameEnd = offset + cmdsize

                if nameStart < nameEnd, nameEnd <= data.count {
                    // 读取 C 字符串
                    let nameData = data.subdata(in: nameStart..<nameEnd)
                    if let fullPath = String(data: nameData, encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) {

                        let name = (fullPath as NSString).lastPathComponent
                        let type: DylibInfo.DylibType = fullPath.contains(".framework/")
                            ? .framework : .dylib

                        let info = DylibInfo(
                            id: UUID().uuidString,
                            name: name,
                            path: fullPath,
                            type: type,
                            isWeakLinked: cmd == MachO.lcLoadWeakDylib
                        )
                        dylibs.append(info)
                    }
                }
            }

            offset += cmdsize
        }

        return dylibs
    }

    /// 解析 FAT 二进制（取第一个架构的 slice）
    private func parseDylibsFromFat(data: Data) throws -> [DylibInfo] {
        guard data.count >= 8 else {
            throw DylibInjectorError.machOParseFailed("FAT 头部不完整")
        }

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let swapped = (magic == MachO.fatMagicSwapped)

        // nfat_arch 在 offset 4
        var nfat = data.subdata(in: 4..<8)
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        if swapped { nfat = nfat.byteSwapped }

        guard nfat > 0 else {
            throw DylibInjectorError.machOParseFailed("FAT 二进制无架构")
        }

        // 第一个 fat_arch 在 offset 8
        // struct fat_arch { cpu_type, cpu_subtype, offset, size, align }
        // offset 在 +8, size 在 +12
        var sliceOffset = data.subdata(in: 16..<20)
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        var sliceSize = data.subdata(in: 20..<24)
            .withUnsafeBytes { $0.load(as: UInt32.self) }

        if swapped {
            sliceOffset = sliceOffset.byteSwapped
            sliceSize = sliceSize.byteSwapped
        }

        let start = Int(sliceOffset)
        let end = start + Int(sliceSize)

        guard end <= data.count else {
            throw DylibInjectorError.machOParseFailed("FAT slice 超出文件范围")
        }

        let sliceData = data.subdata(in: start..<end)
        return try parseDylibs(from: sliceData)
    }

    // MARK: - 注入 dylib

    /// 向 IPA 中的可执行文件注入新的 dylib
    /// - Parameters:
    ///   - dylibName: dylib 文件名（如 "inject.dylib"）
    ///   - dylibFileURL: dylib 文件路径（将被复制到 .app 目录）
    ///   - ipaExtractedDir: 已解压的 IPA 目录
    ///   - weakLink: 是否使用弱链接（LC_LOAD_WEAK_DYLIB）
    func injectDylib(
        dylibName: String,
        dylibFileURL: URL,
        ipaExtractedDir: URL,
        weakLink: Bool = false
    ) throws {
        let fm = FileManager.default
        let executableURL = try findExecutable(in: ipaExtractedDir)
        let appBundleURL = executableURL.deletingLastPathComponent()

        // 1. 复制 dylib 到 .app 目录
        let destDylibURL = appBundleURL.appendingPathComponent(dylibName)
        if fm.fileExists(atPath: destDylibURL.path) {
            try fm.removeItem(at: destDylibURL)
        }
        try fm.copyItem(at: dylibFileURL, to: destDylibURL)

        // 2. 修改 Mach-O 添加 load command
        let loadPath = "@executable_path/\(dylibName)"
        try addLoadDylibCommand(
            executableURL: executableURL,
            dylibPath: loadPath,
            weakLink: weakLink
        )
    }

    /// 向 Mach-O 二进制添加 LC_LOAD_DYLIB 命令（公开接口）
    /// - Parameters:
    ///   - executableURL: 可执行文件路径
    ///   - dylibPath: dylib 的加载路径（如 @executable_path/Frameworks/xxx.dylib）
    ///   - weakLink: 是否弱链接
    func addLoadCommand(
        executableURL: URL,
        dylibPath: String,
        weakLink: Bool
    ) throws {
        try addLoadDylibCommand(executableURL: executableURL, dylibPath: dylibPath, weakLink: weakLink)
    }

    /// 向 Mach-O 二进制添加 LC_LOAD_DYLIB 命令
    /// - Parameters:
    ///   - executableURL: 可执行文件路径
    ///   - dylibPath: dylib 的加载路径（如 @executable_path/inject.dylib）
    ///   - weakLink: 是否弱链接
    private func addLoadDylibCommand(
        executableURL: URL,
        dylibPath: String,
        weakLink: Bool
    ) throws {
        var data = try Data(contentsOf: executableURL)

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }

        // TODO: 处理 FAT 二进制（需要修改所有架构的 slice）
        // 目前仅支持单架构 Mach-O

        let headerSize: Int
        switch magic {
        case MachO.magic64:
            headerSize = MachO.headerSize64
        case MachO.magic32:
            headerSize = MachO.headerSize32
        default:
            throw DylibInjectorError.machOParseFailed("不支持的格式，仅支持单架构 Mach-O")
        }

        // 构建 dylib_command
        let pathBytes = Array(dylibPath.utf8) + [0] // null 结尾
        // 对齐到 8 字节（64 位）或 4 字节（32 位）
        let alignment = (magic == MachO.magic64) ? 8 : 4
        let nameOffset = MachO.dylibCommandBaseSize
        let rawSize = nameOffset + pathBytes.count
        let cmdsize = (rawSize + alignment - 1) / alignment * alignment // 向上对齐

        // 检查是否有足够空间
        let ncmds = Int(data.subdata(in: 16..<20)
            .withUnsafeBytes { $0.load(as: UInt32.self) })
        let sizeofcmds = Int(data.subdata(in: 20..<24)
            .withUnsafeBytes { $0.load(as: UInt32.self) })
        let firstSegmentOffset = headerSize + sizeofcmds

        // TODO: 更精确地检查可用空间
        // 需要找到 __TEXT segment 的 fileoff，确保新 command 不会覆盖代码段
        // 简单检查：新 command 是否能放进 header 和第一个 section 之间的间隙
        let insertOffset = headerSize + sizeofcmds

        // 构建 load command 数据
        var cmdData = Data(count: cmdsize)
        let cmdType: UInt32 = weakLink ? MachO.lcLoadWeakDylib : MachO.lcLoadDylib

        cmdData.withUnsafeMutableBytes { ptr in
            // cmd
            ptr.storeBytes(of: cmdType, toByteOffset: 0, as: UInt32.self)
            // cmdsize
            ptr.storeBytes(of: UInt32(cmdsize), toByteOffset: 4, as: UInt32.self)
            // dylib.name.offset
            ptr.storeBytes(of: UInt32(nameOffset), toByteOffset: 8, as: UInt32.self)
            // dylib.timestamp
            ptr.storeBytes(of: UInt32(2), toByteOffset: 12, as: UInt32.self)
            // dylib.current_version (1.0.0 = 0x10000)
            ptr.storeBytes(of: UInt32(0x10000), toByteOffset: 16, as: UInt32.self)
            // dylib.compatibility_version
            ptr.storeBytes(of: UInt32(0x10000), toByteOffset: 20, as: UInt32.self)
        }

        // 写入路径字符串
        for (i, byte) in pathBytes.enumerated() {
            cmdData[nameOffset + i] = byte
        }

        // TODO: 实际写入前需要验证安全性
        // - 确认 insertOffset + cmdsize 不会超过第一个 section 的 offset
        // - 如果空间不够，需要扩展 __TEXT segment 或使用 __LINKEDIT 方案
        // - 当前实现是概念验证，生产环境需要更完善的 Mach-O 操作

        // 在 load commands 末尾插入新命令
        if insertOffset + cmdsize > data.count {
            throw DylibInjectorError.noAvailableSpace
        }

        // 将新 command 写入（覆盖填充区域）
        data.replaceSubrange(insertOffset..<(insertOffset + cmdsize), with: cmdData)

        // 更新 header: ncmds + 1, sizeofcmds + cmdsize
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(ncmds + 1), toByteOffset: 16, as: UInt32.self)
            ptr.storeBytes(of: UInt32(sizeofcmds + cmdsize), toByteOffset: 20, as: UInt32.self)
        }

        // 写回文件
        try data.write(to: executableURL)
    }

    // MARK: - 移除 dylib

    /// 从 IPA 中移除指定的 dylib
    /// - Parameters:
    ///   - dylibPath: dylib 的加载路径（DylibInfo.path）
    ///   - ipaExtractedDir: 已解压的 IPA 目录
    func removeDylib(dylibPath: String, ipaExtractedDir: URL) throws {
        let executableURL = try findExecutable(in: ipaExtractedDir)
        var data = try Data(contentsOf: executableURL)

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }

        let headerSize: Int
        switch magic {
        case MachO.magic64: headerSize = MachO.headerSize64
        case MachO.magic32: headerSize = MachO.headerSize32
        default:
            throw DylibInjectorError.machOParseFailed("不支持的格式")
        }

        let ncmds = Int(data.subdata(in: 16..<20)
            .withUnsafeBytes { $0.load(as: UInt32.self) })
        let sizeofcmds = Int(data.subdata(in: 20..<24)
            .withUnsafeBytes { $0.load(as: UInt32.self) })

        var offset = headerSize
        var found = false

        for _ in 0..<ncmds {
            guard offset + MachO.loadCommandHeaderSize <= data.count else { break }

            let cmd = data.subdata(in: offset..<(offset + 4))
                .withUnsafeBytes { $0.load(as: UInt32.self) }
            let cmdsize = Int(data.subdata(in: (offset + 4)..<(offset + 8))
                .withUnsafeBytes { $0.load(as: UInt32.self) })

            guard cmdsize > 0 else { break }

            if cmd == MachO.lcLoadDylib || cmd == MachO.lcLoadWeakDylib {
                // 读取 dylib 路径
                let nameOffset = Int(data.subdata(in: (offset + 8)..<(offset + 12))
                    .withUnsafeBytes { $0.load(as: UInt32.self) })
                let nameStart = offset + nameOffset
                let nameEnd = offset + cmdsize

                if nameStart < nameEnd, nameEnd <= data.count {
                    let nameData = data.subdata(in: nameStart..<nameEnd)
                    if let path = String(data: nameData, encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
                       path == dylibPath {

                        // 找到目标：用零填充该 load command
                        let zeroData = Data(count: cmdsize)
                        data.replaceSubrange(offset..<(offset + cmdsize), with: zeroData)

                        // TODO: 更正确的做法是将后续 load commands 前移，
                        // 而不是简单地用零填充，因为零填充可能导致 codesign 验证失败
                        // 这里需要将 offset 后面的所有 commands 向前移动 cmdsize 字节

                        // 更新 header
                        data.withUnsafeMutableBytes { ptr in
                            ptr.storeBytes(of: UInt32(ncmds - 1), toByteOffset: 16, as: UInt32.self)
                            ptr.storeBytes(of: UInt32(sizeofcmds - cmdsize), toByteOffset: 20, as: UInt32.self)
                        }

                        found = true
                        break
                    }
                }
            }

            offset += cmdsize
        }

        guard found else {
            throw DylibInjectorError.dylibNotFound(dylibPath)
        }

        // 写回文件
        try data.write(to: executableURL)

        // 尝试删除对应的 dylib 文件（如果在 .app 目录内）
        let appBundleURL = executableURL.deletingLastPathComponent()
        if dylibPath.hasPrefix("@executable_path/") {
            let relativeName = String(dylibPath.dropFirst("@executable_path/".count))
            let dylibFileURL = appBundleURL.appendingPathComponent(relativeName)
            try? FileManager.default.removeItem(at: dylibFileURL)
        }
    }

    // MARK: - 辅助方法

    /// 在解压目录中定位 .app 包中的可执行文件
    private func findExecutable(in ipaExtractedDir: URL) throws -> URL {
        let payloadDir = ipaExtractedDir.appendingPathComponent("Payload", isDirectory: true)

        guard FileManager.default.fileExists(atPath: payloadDir.path) else {
            throw DylibInjectorError.appBundleNotFound
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: payloadDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw DylibInjectorError.appBundleNotFound
        }

        // 从 Info.plist 读取 CFBundleExecutable
        let plistURL = appBundle.appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any],
              let execName = plist["CFBundleExecutable"] as? String else {
            throw DylibInjectorError.executableNotFound
        }

        let executableURL = appBundle.appendingPathComponent(execName)

        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw DylibInjectorError.executableNotFound
        }

        return executableURL
    }

    /// 列出 .app 目录中所有的 dylib 和 framework 文件
    /// 这些是物理文件，不一定都在 load commands 中
    func listDylibFiles(in ipaExtractedDir: URL) throws -> [URL] {
        let executableURL = try findExecutable(in: ipaExtractedDir)
        let appBundleURL = executableURL.deletingLastPathComponent()
        let fm = FileManager.default

        var dylibFiles: [URL] = []

        guard let enumerator = fm.enumerator(
            at: appBundleURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "dylib" || ext == "framework" {
                dylibFiles.append(fileURL)
            }
        }

        return dylibFiles
    }
}
