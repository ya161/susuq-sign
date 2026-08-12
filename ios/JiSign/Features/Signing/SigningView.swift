import SwiftUI
import UIKit
import PhotosUI

struct SigningView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedIPAs: [StoredIPA] = []
    @State private var selectedCert: Certificate?

    // 基础选项
    @State private var newAppName = ""
    @State private var newBundleID = ""
    @State private var multiOpenEnabled = true
    @State private var multiOpenCount = 1
    @State private var multiOpenStartIndex = UserDefaults.standard.integer(forKey: "multiOpenStartIndex").clamped(min: 1)
    @State private var changeIcon = false
    @State private var customIcon: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 高级选项
    @State private var showAdvanced = false
    @State private var removeVersionLimit = false
    @State private var removeDeviceLimit = false
    @State private var fixWhiteIcon = false
    @State private var enableFileSharing = false
    @State private var removeURLSchemes = false
    @State private var removeExtensions = false
    // Hook 选项
    @State private var removeUpdateCheck = false
    @State private var removeClipboard = false
    @State private var removeJailbreakDetection = false
    @State private var removeAppJumpDetection = false

    // UI 状态
    @State private var showIPAPicker = false
    @State private var showCertPicker = false
    @State private var isSigning = false
    @State private var signProgress: Double = 0
    @State private var signMessage = ""
    @State private var signLogs: [String] = []  // 真实签名日志
    @State private var signedCount = 0
    @State private var showResult = false
    @State private var signError: String?
    @State private var showError = false
    @State private var lastSignedIPA: URL?
    @State private var allSignedIPAs: [(path: URL, bundleID: String)] = []
    @State private var lastOriginalIPA: URL?
    @State private var lastSignedName = ""
    @State private var lastSignedBundleID = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - 1. IPA + 证书选择
                    SelectionCard(
                        title: "选择 IPA",
                        icon: "doc.zipper",
                        value: ipaSelectionText,
                        isEmpty: selectedIPAs.isEmpty
                    ) { showIPAPicker = true }

                    SelectionCard(
                        title: "选择证书",
                        icon: "shield.checkered",
                        value: selectedCert?.displayName ?? "点击选择签名证书",
                        isEmpty: selectedCert == nil
                    ) { showCertPicker = true }

                    // MARK: - 2. 基础选项
                    VStack(alignment: .leading, spacing: 14) {
                        Text("应用设置")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        // 多开模式
                        VStack(spacing: 10) {
                            Toggle(isOn: $multiOpenEnabled) {
                                OptionLabel(icon: "square.on.square", title: "多开模式", subtitle: "自动修改 Bundle ID 实现分身")
                            }
                            .tint(.jsPrimary)

                            if multiOpenEnabled {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("数量")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Stepper("\(multiOpenCount)", value: $multiOpenCount, in: 1...99)
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("起始序号")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Stepper("\(multiOpenStartIndex)", value: $multiOpenStartIndex, in: 1...999)
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .padding(.leading, 36)
                            }
                        }

                        Divider()

                        // 修改名称
                        HStack(spacing: 10) {
                            Image(systemName: "textformat")
                                .foregroundColor(.jsPrimary)
                                .frame(width: 22)
                            TextField("App 名称（留空保持原始）", text: $newAppName)
                                .font(.subheadline)
                        }

                        // 修改 Bundle ID
                        HStack(spacing: 10) {
                            Image(systemName: "number")
                                .foregroundColor(.jsPrimary)
                                .frame(width: 22)
                            TextField("Bundle ID（留空自动处理）", text: $newBundleID)
                                .font(.subheadline)
                                .autocapitalization(.none)
                        }

                        Divider()

                        // 自定义图标
                        Toggle(isOn: $changeIcon) {
                            OptionLabel(icon: "photo", title: "自定义图标", subtitle: "从相册选择替换 App 图标")
                        }
                        .tint(.jsPrimary)

                        if changeIcon {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack {
                                    if let icon = customIcon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 48, height: 48)
                                            .cornerRadius(10)
                                    } else {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.jsPrimary.opacity(0.1))
                                            .frame(width: 48, height: 48)
                                            .overlay(
                                                Image(systemName: "photo.badge.plus")
                                                    .foregroundColor(.jsPrimary)
                                            )
                                    }
                                    Text(customIcon == nil ? "点击选择图标" : "点击更换图标")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                            .padding(.leading, 36)
                            .onChange(of: selectedPhotoItem) { item in
                                Task {
                                    if let data = try? await item?.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        customIcon = image
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)

                    // MARK: - 3. 高级选项
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.2")
                                    .foregroundColor(.jsPrimary)
                                Text("高级选项")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding()
                        }

                        if showAdvanced {
                            VStack(alignment: .leading, spacing: 12) {
                                // 兼容性修复
                                Text("兼容性")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)

                                AdvancedToggle(icon: "arrow.uturn.down.circle", title: "移除系统版本限制", subtitle: "允许在旧版 iOS 上运行", isOn: $removeVersionLimit)
                                AdvancedToggle(icon: "ipad.and.iphone", title: "移除设备类型限制", subtitle: "iPad App 在 iPhone 上运行", isOn: $removeDeviceLimit)
                                AdvancedToggle(icon: "app.dashed", title: "修复白图标", subtitle: "修复签名后图标变白问题", isOn: $fixWhiteIcon)

                                Divider().padding(.horizontal)

                                // 权限配置
                                Text("权限")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)

                                AdvancedToggle(icon: "folder", title: "启用文件共享", subtitle: "允许通过 iTunes 访问文件", isOn: $enableFileSharing)
                                AdvancedToggle(icon: "link.badge.plus", title: "移除 URL Schemes", subtitle: "防止应用间跳转检测", isOn: $removeURLSchemes)
                                AdvancedToggle(icon: "puzzlepiece.extension", title: "移除 App Extensions", subtitle: "移除通知、分享等扩展", isOn: $removeExtensions)

                                Divider().padding(.horizontal)

                                // Hook 功能
                                Text("Hook")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)

                                AdvancedToggle(icon: "arrow.uturn.down.circle", title: "移除版本更新检测", subtitle: "屏蔽 App 内的升级提示", isOn: $removeUpdateCheck)
                                AdvancedToggle(icon: "doc.on.clipboard", title: "移除剪贴板识别", subtitle: "防止 App 读取剪贴板内容", isOn: $removeClipboard)
                                AdvancedToggle(icon: "lock.shield", title: "移除越狱检测", subtitle: "绕过 App 的越狱环境检测", isOn: $removeJailbreakDetection)
                                AdvancedToggle(icon: "arrow.right.arrow.left", title: "移除跳转检测", subtitle: "防止 App 检测其他 App 安装状态", isOn: $removeAppJumpDetection)
                            }
                            .padding(.bottom)
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(16)

                    // MARK: - 4. 签名按钮
                    Button {
                        startSigning()
                    } label: {
                        HStack(spacing: 8) {
                            if isSigning {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "signature")
                            }
                            Text(signButtonText)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSign ? Color.jsPrimary : Color(.systemGray4))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(!canSign || isSigning)

                    // 签名进度
                    if isSigning {
                        VStack(spacing: 6) {
                            ProgressView(value: signProgress)
                                .tint(.jsPrimary)
                            Text(signMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("签名")
            .sheet(isPresented: $showIPAPicker) {
                IPAPickerView(selectedIPAs: $selectedIPAs)
            }
            .sheet(isPresented: $showCertPicker) {
                CertPickerView(selectedCert: $selectedCert)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showResult) {
                SignResultView(
                    signedIPAPath: lastSignedIPA,
                    allSignedIPAs: allSignedIPAs,
                    originalIPAPath: lastOriginalIPA,
                    appName: lastSignedName,
                    bundleID: lastSignedBundleID,
                    signedCount: signedCount,
                    realSignLogs: signLogs
                )
            }
            .alert("签名失败", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(signError ?? "未知错误")
            }
        }
    }

    // MARK: - 计算属性

    private var ipaSelectionText: String {
        if selectedIPAs.isEmpty { return "点击选择 IPA 文件" }
        if selectedIPAs.count == 1 {
            return selectedIPAs[0].info?.displayName ?? selectedIPAs[0].fileName
        }
        return "\(selectedIPAs.count) 个文件已选择"
    }

    private var canSign: Bool {
        !selectedIPAs.isEmpty && selectedCert != nil
    }

    private var totalSignCount: Int {
        if multiOpenEnabled && selectedIPAs.count == 1 {
            return multiOpenCount
        }
        return selectedIPAs.count
    }

    private var signButtonText: String {
        if isSigning { return "签名中..." }
        let count = totalSignCount
        if count > 1 { return "批量签名 (\(count) 个)" }
        return "开始签名"
    }

    // MARK: - 签名逻辑

    private func startSigning() {
        guard let cert = selectedCert,
              let p12Path = cert.p12Path,
              let mpPath = cert.mobileprovisionPath else {
            signError = "证书文件不完整，请重新选择或下载证书"
            showError = true
            return
        }

        isSigning = true
        signProgress = 0
        signedCount = 0
        allSignedIPAs = []
        signLogs = []
        signMessage = "准备签名..."

        Task {
            do {
                for ipa in selectedIPAs {
                    // 确保 IPA 信息已解析（如果未缓存，同步解析一次）
                    var realAppName = ipa.info?.displayName
                    var realBundleID = ipa.info?.bundleIdentifier
                    if realBundleID == nil {
                        if let detail = try? IPAStorage.shared.getIPADetail(id: ipa.id) {
                            realAppName = detail.info?.displayName
                            realBundleID = detail.info?.bundleIdentifier
                        }
                    }
                    let cleanFileName = ipa.fileName.replacingOccurrences(of: ".ipa", with: "")
                    let baseAppName = !newAppName.isEmpty ? newAppName : (realAppName ?? cleanFileName)
                    let baseBundleID = !newBundleID.isEmpty ? newBundleID : (realBundleID ?? "com.app")

                    // 确定要签名的数量和 bundle ID 列表
                    let count = (multiOpenEnabled && selectedIPAs.count == 1) ? multiOpenCount : 1
                    for i in 0..<count {
                        let idx = multiOpenStartIndex + i
                        let cloneBundleID: String?
                        if multiOpenEnabled {
                            cloneBundleID = "\(baseBundleID).clone\(idx)"
                        } else {
                            cloneBundleID = newBundleID.isEmpty ? nil : newBundleID
                        }

                        let options = IPASigner.SignOptions(
                            ipaPath: ipa.filePath,
                            p12Path: p12Path,
                            mobileprovisionPath: mpPath,
                            p12Password: "1",
                            newBundleID: cloneBundleID,
                            newAppName: baseAppName,
                            customIcon: changeIcon ? customIcon : nil,
                            removeVersionLimit: removeVersionLimit,
                            removeDeviceLimit: removeDeviceLimit,
                            enableFileSharing: enableFileSharing,
                            removeURLSchemes: removeURLSchemes,
                            removeExtensions: removeExtensions,
                            removeUpdateCheck: removeUpdateCheck,
                            removeClipboard: removeClipboard,
                            removeJailbreakDetection: removeJailbreakDetection,
                            removeAppJumpDetection: removeAppJumpDetection
                        )

                        await MainActor.run {
                            signMessage = count > 1 ? "签名 \(i+1)/\(count)..." : "签名 \(baseAppName)..."
                            signProgress = Double(i) / Double(count)
                        }

                        let signResult = try await IPASigner.shared.sign(options: options) { pct, msg in
                            signProgress = (Double(i) + pct) / Double(count)
                            if !msg.isEmpty { signLogs.append(msg) }
                        }

                        lastSignedIPA = signResult.signedIPAPath
                        allSignedIPAs.append((path: signResult.signedIPAPath, bundleID: cloneBundleID ?? signResult.bundleID))
                        lastOriginalIPA = ipa.filePath
                        lastSignedBundleID = cloneBundleID ?? signResult.bundleID
                        lastSignedName = baseAppName
                        signedCount += 1
                    }
                }

                if multiOpenEnabled {
                    multiOpenStartIndex += multiOpenCount
                    UserDefaults.standard.set(multiOpenStartIndex, forKey: "multiOpenStartIndex")
                }

                await MainActor.run {
                    isSigning = false
                    signProgress = 1.0
                    showResult = true
                }
            } catch {
                await MainActor.run {
                    isSigning = false
                    signError = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - 选项标签组件

struct OptionLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.jsPrimary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 高级选项 Toggle

struct AdvancedToggle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.jsPrimary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .tint(.jsPrimary)
        .padding(.horizontal)
    }
}

// MARK: - 选择卡片

struct SelectionCard: View {
    let title: String
    let icon: String
    let value: String
    let isEmpty: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.jsPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.jsPrimary.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(value)
                        .font(.caption)
                        .foregroundColor(isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - IPA 选择器

struct IPAPickerView: View {
    @Binding var selectedIPAs: [StoredIPA]
    @Environment(\.dismiss) private var dismiss
    @State private var allIPAs: [StoredIPA] = []
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if allIPAs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("暂无 IPA 文件")
                            .foregroundColor(.secondary)
                        Text("请先在「IPA」页面导入文件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(allIPAs) { ipa in
                            Button {
                                if selectedIDs.contains(ipa.id) {
                                    selectedIDs.remove(ipa.id)
                                } else {
                                    selectedIDs.insert(ipa.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedIDs.contains(ipa.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedIDs.contains(ipa.id) ? .jsPrimary : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ipa.info?.displayName ?? ipa.fileName)
                                            .foregroundColor(.primary)
                                        Text(ipa.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择 IPA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定 (\(selectedIDs.count))") {
                        selectedIPAs = allIPAs.filter { selectedIDs.contains($0.id) }
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .onAppear {
                allIPAs = IPAStorage.shared.listIPAs()
                selectedIDs = Set(selectedIPAs.map { $0.id })
            }
        }
    }
}

// MARK: - 证书选择器

struct CertPickerView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedCert: Certificate?
    @Environment(\.dismiss) private var dismiss
    @State private var certs: [Certificate] = []
    @State private var showImportCert = false

    var body: some View {
        NavigationStack {
            Group {
                if certs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("暂无证书")
                            .foregroundColor(.secondary)
                        Text("请先在「证书」页面购买或导入")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(certs) { cert in
                            Button {
                                selectedCert = cert
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(cert.displayName)
                                            .foregroundColor(.primary)
                                        Text("批次: \(cert.batchNo)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(cert.p12Path != nil ? "证书已就绪" : "需下载证书文件")
                                            .font(.caption2)
                                            .foregroundColor(cert.p12Path != nil ? .green : .orange)
                                    }
                                    Spacer()
                                    if selectedCert?.batchNo == cert.batchNo {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.jsPrimary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择证书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImportCert = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showImportCert) {
                ImportCertView { batchNo in
                    loadCerts()
                    // 自动选中新导入的证书
                    if let cert = certs.first(where: { $0.batchNo == batchNo }) {
                        selectedCert = cert
                        dismiss()
                    }
                }
            }
            .onAppear { loadCerts() }
        }
    }

    private func loadCerts() {
        let saved = CertStorage.shared.listCerts()
        certs = saved.map { cert in
            Certificate(displayName: "个人开发者证书", batchNo: cert.batchNo, expireDate: nil, p12Path: cert.p12Path, mobileprovisionPath: cert.mobileprovisionPath)
        }
        guard appState.isLoggedIn else { return }
        Task {
            do {
                let resp = try await APIClient.shared.getCertList()
                guard let remoteCerts = resp.data else { return }
                let localBatchNos = Set(saved.map { $0.batchNo })
                let newCerts = remoteCerts.filter { !localBatchNos.contains($0.batchNo) }
                await MainActor.run {
                    for cert in newCerts {
                        certs.append(Certificate(displayName: "个人开发者证书", batchNo: cert.batchNo, expireDate: nil, p12Path: nil, mobileprovisionPath: nil))
                    }
                }
            } catch {}
        }
    }
}

// MARK: - 手动导入证书

struct ImportCertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var p12URL: URL?
    @State private var mpURL: URL?
    @State private var showP12Picker = false
    @State private var showMPPicker = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showError = false

    var onImported: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // P12 证书
                    Button {
                        showP12Picker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.jsPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("P12 证书文件")
                                    .foregroundColor(.primary)
                                Text(p12URL?.lastPathComponent ?? "点击选择 .p12 文件")
                                    .font(.caption)
                                    .foregroundColor(p12URL != nil ? .green : .secondary)
                            }
                            Spacer()
                            if p12URL != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    // MobileProvision
                    Button {
                        showMPPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.jsPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MobileProvision 文件")
                                    .foregroundColor(.primary)
                                Text(mpURL?.lastPathComponent ?? "点击选择 .mobileprovision 文件")
                                    .font(.caption)
                                    .foregroundColor(mpURL != nil ? .green : .secondary)
                            }
                            Spacer()
                            if mpURL != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } header: {
                    Text("选择证书文件")
                } footer: {
                    Text("导入你自己的 P12 证书和描述文件，用于 IPA 签名")
                }

                Section {
                    Button {
                        importCert()
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                            Text("导入证书")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canImport ? Color.jsPrimary : Color(.systemGray4))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!canImport || isImporting)
                }
            }
            .navigationTitle("导入证书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showP12Picker,
                allowedContentTypes: [.init(filenameExtension: "p12")!]
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    p12URL = url
                }
            }
            .fileImporter(
                isPresented: $showMPPicker,
                allowedContentTypes: [.init(filenameExtension: "mobileprovision")!]
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    mpURL = url
                }
            }
            .alert("导入失败", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(importError ?? "未知错误")
            }
        }
    }

    private var canImport: Bool {
        p12URL != nil && mpURL != nil
    }

    private func importCert() {
        guard let p12 = p12URL, let mp = mpURL else { return }

        isImporting = true
        let batchNo = "imported_\(Int(Date().timeIntervalSince1970))"

        do {
            _ = try CertStorage.shared.importCert(
                p12URL: p12,
                mobileprovisionURL: mp,
                batchNo: batchNo
            )
            isImporting = false
            onImported(batchNo)
            dismiss()
        } catch {
            isImporting = false
            importError = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 工具扩展

extension Int {
    func clamped(min: Int) -> Int { self < min ? min : self }
}

// MARK: - 模型

struct IPAFile: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let version: String
    let size: Int64
    let path: URL
}

struct Certificate: Identifiable {
    let id = UUID()
    let displayName: String
    let batchNo: String
    let expireDate: Date?
    let p12Path: URL?
    let mobileprovisionPath: URL?
}
