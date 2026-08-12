import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CertStoreView: View {
    @EnvironmentObject var appState: AppState
    @State private var certificates: [Certificate] = []
    @State private var showPurchase = false
    // showImportCert 不再需要，改用直接 UIKit 弹出
    @State private var showImportSuccess = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 购买证书卡片
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("个人开发者证书")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("绑定设备 UDID，有效期约 1 年")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("¥69")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.jsPrimary)
                        }

                        // 功能说明
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "checkmark.circle.fill", text: "有效期内无限次签名")
                            FeatureRow(icon: "checkmark.circle.fill", text: "支持多开、改名、注入插件")
                            FeatureRow(icon: "checkmark.circle.fill", text: "自动获取 UDID，无需手动操作")
                            FeatureRow(icon: "checkmark.circle.fill", text: "证书过期提醒")
                        }

                        Button {
                            showPurchase = true
                        } label: {
                            Text("立即购买")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.jsPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.jsPrimary.opacity(0.3), lineWidth: 1)
                            )
                    )

                    // 已购证书列表
                    VStack(alignment: .leading, spacing: 12) {
                        Text("我的证书")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        if certificates.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "shield.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("暂无证书")
                                    .foregroundColor(.secondary)
                                Text("购买证书后即可签名 IPA 文件")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(certificates) { cert in
                                CertCard(certificate: cert) {
                                    loadCertificates()
                                }
                            }
                        }
                    }

                    // 导入已有证书
                    Button {
                        openCertFilePicker()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("导入已有证书")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .foregroundColor(.jsPrimary)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("证书")
            .onAppear { loadCertificates() }
            .sheet(isPresented: $showPurchase) {
                PurchaseView()
                    .environmentObject(appState)
            }
            .alert("导入成功", isPresented: $showImportSuccess) {
                Button("确定") {}
            } message: {
                Text("证书已导入，可在签名时使用")
            }
            .alert("导入失败", isPresented: $showImportError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
        }
    }

    /// 直接从 UIKit 层弹出文档选择器
    private func openCertFilePicker() {
        let types: [UTType] = [.data, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        let delegate = FilePickerDelegate { [self] urls in
            handleCertImport(urls)
        }
        objc_setAssociatedObject(picker, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        picker.delegate = delegate

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(picker, animated: true)
    }

    private func handleCertImport(_ urls: [URL]) {
        var p12URL: URL?
        var mpURL: URL?
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "p12" || ext == "pfx" { p12URL = url }
            if ext == "mobileprovision" { mpURL = url }
        }
        guard let p12 = p12URL, let mp = mpURL else {
            importErrorMessage = "请同时选择 .p12 证书文件和 .mobileprovision 描述文件（长按可多选）"
            showImportError = true
            return
        }
        let batchNo = "imported_\(Int(Date().timeIntervalSince1970))"
        do {
            let _ = try CertStorage.shared.importCert(p12URL: p12, mobileprovisionURL: mp, batchNo: batchNo)
            loadCertificates()
            showImportSuccess = true
        } catch {
            importErrorMessage = "导入失败: \(error.localizedDescription)"
            showImportError = true
        }
    }

    private func loadCertificates() {
        // 先加载本地证书
        let saved = CertStorage.shared.listCerts()
        certificates = saved.map { cert in
            Certificate(
                displayName: "个人开发者证书",
                batchNo: cert.batchNo,
                expireDate: nil,
                p12Path: cert.p12Path,
                mobileprovisionPath: cert.mobileprovisionPath
            )
        }

        // 如果已登录，从后端同步证书列表
        guard appState.isLoggedIn else { return }
        Task {
            do {
                let resp = try await APIClient.shared.getCertList()
                guard let certs = resp.data, !certs.isEmpty else { return }
                let localBatchNos = Set(saved.map { $0.batchNo })
                let remoteCerts = certs.filter { !localBatchNos.contains($0.batchNo) }
                if !remoteCerts.isEmpty {
                    await MainActor.run {
                        for cert in remoteCerts {
                            certificates.append(Certificate(
                                displayName: "个人开发者证书",
                                batchNo: cert.batchNo,
                                expireDate: nil,
                                p12Path: nil,
                                mobileprovisionPath: nil
                            ))
                        }
                    }
                }
            } catch {
                // 网络失败不影响本地证书显示
            }
        }
    }
}

// MARK: - 功能行

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 证书卡片

struct CertCard: View {
    let certificate: Certificate
    let onDownloaded: (() -> Void)?
    @State private var showShareSheet = false
    @State private var exportURLs: [URL] = []
    @State private var isDownloading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    init(certificate: Certificate, onDownloaded: (() -> Void)? = nil) {
        self.certificate = certificate
        self.onDownloaded = onDownloaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(certificate.displayName)
                        .fontWeight(.medium)
                    if let expire = certificate.expireDate {
                        Text("到期: \(expire, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("批次: \(certificate.batchNo)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if certificate.p12Path != nil {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("本地").font(.caption2).foregroundColor(.green)
                    }
                } else {
                    Text("云端")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            // 操作按钮
            HStack(spacing: 10) {
                if certificate.p12Path != nil {
                    // 导出按钮
                    Button {
                        exportCert()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("导出证书")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.jsPrimary.opacity(0.1))
                        .foregroundColor(.jsPrimary)
                        .cornerRadius(8)
                    }
                } else {
                    // 下载到本地按钮
                    Button {
                        downloadCert()
                    } label: {
                        HStack(spacing: 4) {
                            if isDownloading {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(isDownloading ? "下载中..." : "下载到本地")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isDownloading)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .background(
            // 用隐藏视图触发 UIActivityViewController，避免 SwiftUI sheet 的时序问题
            ExportTrigger(isPresented: $showShareSheet, urls: exportURLs)
        )
        .alert(alertTitle, isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func exportCert() {
        // 复制到临时目录并用可读文件名
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("cert_export_\(certificate.batchNo)")
        try? FileManager.default.removeItem(at: tmpDir)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        var urls: [URL] = []
        if let p12 = certificate.p12Path {
            let dest = tmpDir.appendingPathComponent("\(certificate.batchNo).p12")
            try? FileManager.default.copyItem(at: p12, to: dest)
            urls.append(dest)
        }
        if let mp = certificate.mobileprovisionPath {
            let dest = tmpDir.appendingPathComponent("\(certificate.batchNo).mobileprovision")
            try? FileManager.default.copyItem(at: mp, to: dest)
            urls.append(dest)
        }

        guard !urls.isEmpty else {
            alertTitle = "导出失败"
            alertMessage = "证书文件不存在，请重新下载"
            showAlert = true
            return
        }
        exportURLs = urls
        showShareSheet = true
    }

    private func downloadCert() {
        isDownloading = true
        Task {
            do {
                let resp = try await APIClient.shared.downloadCert(batchNo: certificate.batchNo)
                if let data = resp.data {
                    let paths = try CertStorage.shared.saveCert(
                        batchNo: certificate.batchNo,
                        p12Base64: data.p12Data,
                        mobileprovisionBase64: data.mobileprovisionData
                    )
                    await MainActor.run {
                        isDownloading = false
                        alertTitle = "下载成功"
                        alertMessage = "证书已保存到本地，可在签名时直接使用，也可点击「导出证书」分享给其他签名工具"
                        showAlert = true
                        onDownloaded?()
                    }
                } else {
                    await MainActor.run {
                        isDownloading = false
                        alertTitle = "下载失败"
                        alertMessage = resp.error ?? "未知错误"
                        showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    alertTitle = "下载失败"
                    alertMessage = "网络错误: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - 导出触发器（避免 SwiftUI sheet 时序问题）

struct ExportTrigger: UIViewRepresentable {
    @Binding var isPresented: Bool
    let urls: [URL]

    func makeUIView(context: Context) -> UIView {
        UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if isPresented && !urls.isEmpty {
            DispatchQueue.main.async {
                isPresented = false
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.windows.first?.rootViewController else { return }

                // 找到最顶层的 ViewController
                var top = root
                while let presented = top.presentedViewController {
                    top = presented
                }

                let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
                activityVC.popoverPresentationController?.sourceView = uiView
                top.present(activityVC, animated: true)
            }
        }
    }
}

// MARK: - 购买流程

struct PurchaseView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: PurchaseStep = .collectUDID
    @State private var udid = ""
    @State private var isLoading = false
    @State private var udidCheckTimer: Timer?
    @State private var pollingTask: Task<Void, Never>?
    @State private var pendingOrderNo = ""
    @State private var manualUDID = ""
    @State private var showManualInput = false
    @State private var showLoginAlert = false

    /// pending 订单本地持久化 key
    private static let pendingOrderKey = "jisign_pending_order_no"

    enum PurchaseStep {
        case collectUDID
        case waitingUDID
        case payment
        case generating
        case complete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 步骤指示器
                HStack(spacing: 0) {
                    StepDot(number: 1, title: "获取UDID", isActive: step == .collectUDID || step == .waitingUDID, isDone: step == .payment || step == .generating || step == .complete)
                    StepLine(isDone: step == .payment || step == .generating || step == .complete)
                    StepDot(number: 2, title: "支付", isActive: step == .payment, isDone: step == .generating || step == .complete)
                    StepLine(isDone: step == .generating || step == .complete)
                    StepDot(number: 3, title: "生成证书", isActive: step == .generating, isDone: step == .complete)
                }
                .padding(.horizontal)

                switch step {
                case .collectUDID:
                    VStack(spacing: 16) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 60))
                            .foregroundColor(.jsPrimary)
                        Text("第 1 步：获取设备 UDID")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("点击下方按钮，将跳转 Safari 安装描述文件，系统会自动获取您设备的 UDID")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button {
                            collectUDID()
                        } label: {
                            HStack {
                                Image(systemName: "safari")
                                Text("前往获取 UDID")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.jsPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        // 手动输入 UDID 选项
                        Button {
                            showManualInput.toggle()
                        } label: {
                            Text("已有 UDID？手动输入")
                                .font(.subheadline)
                                .foregroundColor(.jsPrimary)
                        }

                        if showManualInput {
                            VStack(spacing: 10) {
                                TextField("粘贴你的设备 UDID", text: $manualUDID)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))

                                Button {
                                    if !manualUDID.isEmpty {
                                        udid = manualUDID
                                        step = .payment
                                    }
                                } label: {
                                    Text("确认并继续")
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(manualUDID.isEmpty ? Color.gray : Color.jsPrimary)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                .disabled(manualUDID.isEmpty)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        // 提示
                        VStack(alignment: .leading, spacing: 6) {
                            Label("描述文件安装后会自动删除，不会留在设备上", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Label("UDID 是设备唯一标识，用于生成专属证书", systemImage: "lock.shield")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                case .waitingUDID:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("等待获取 UDID...")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("请在 Safari 中完成描述文件安装\n安装后返回此页面将自动继续")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            // 手动跳过等待（如果用户已经获取过 UDID）
                            step = .collectUDID
                            showManualInput = true
                        } label: {
                            Text("已获取？手动输入 UDID")
                                .font(.subheadline)
                                .foregroundColor(.jsPrimary)
                        }
                    }

                case .payment:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("UDID 已获取")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(udid.isEmpty ? "" : String(udid.prefix(8)) + "..." + String(udid.suffix(4)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))

                        Divider()

                        Text("第 2 步：支付 ¥69")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("个人开发者证书，有效期约 1 年\n有效期内无限次签名")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // 仅支付宝
                        Button {
                            processPayment()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "a.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                Text("支付宝支付")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("¥69")
                                    .fontWeight(.bold)
                                    .foregroundColor(.jsPrimary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }

                case .generating:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("第 3 步：生成证书")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("正在向 Apple 申请开发者证书...\n大约需要 1-2 分钟，请稍候")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .complete:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("证书已就绪！")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("现在可以去签名 IPA 了")
                            .foregroundColor(.secondary)

                        Button {
                            dismiss()
                        } label: {
                            Text("开始签名")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.jsPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("购买证书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                autoLoadUDID()
                resumePendingOrder()
            }
            .onDisappear { cleanupTimers() }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    // App 从后台回来（如支付宝返回），尝试恢复订单
                    resumePendingOrder()
                }
            }
            .alert("请先登录", isPresented: $showLoginAlert) {
                Button("确定", role: .cancel) { dismiss() }
            } message: {
                Text("请先登录后再购买证书")
            }
            .alert("提示", isPresented: $showPaymentError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(paymentError)
            }
        }
    }

    private func collectUDID() {
        // 检查用户是否已登录
        let userID = String(appState.currentUser?.id ?? 0)
        if userID == "0" {
            showLoginAlert = true
            return
        }

        // 确保有 UDID 签名令牌（没有就先拉一次）
        Task {
            if APIClient.shared.cachedUdidSig == nil {
                _ = try? await APIClient.shared.getUdidSign()
            }
            await MainActor.run {
                // 跳转 Safari 安装 mobileconfig 获取 UDID（URL 自带 sig）
                if let url = URL(string: APIClient.shared.udidConfigURL(userID: userID)) {
                    UIApplication.shared.open(url)
                }
                step = .waitingUDID
            }
        }

        // 轮询检查 UDID 是否已获取（每 3 秒检查一次，最多 2 分钟）
        var checkCount = 0
        udidCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
            checkCount += 1
            if checkCount > 40 { // 2分钟超时
                timer.invalidate()
                step = .collectUDID
                showManualInput = true
                return
            }
            // 调用 API 检查 UDID 是否已获取
            Task {
                do {
                    let response = try await APIClient.shared.checkUDID(userID: userID)
                    if let data = response.data, data.found, let foundUDID = data.udid {
                        await MainActor.run {
                            udid = foundUDID
                            timer.invalidate()
                            udidCheckTimer = nil
                            step = .payment
                        }
                    }
                } catch {
                    print("[UDIDCheck] 检查 UDID 失败: \(error)")
                }
            }
        }
    }

    @State private var paymentError = ""
    @State private var showPaymentError = false

    /// 自动加载已获取的 UDID
    private func autoLoadUDID() {
        guard appState.isLoggedIn else { return }
        let userID = String(appState.currentUser?.id ?? 0)
        guard userID != "0" else { return }
        Task {
            do {
                let response = try await APIClient.shared.checkUDID(userID: userID)
                if let data = response.data, data.found, let foundUDID = data.udid {
                    await MainActor.run {
                        udid = foundUDID
                        manualUDID = foundUDID
                        step = .payment
                    }
                }
            } catch {
                // 网络失败不影响，用户可手动操作
            }
        }
    }

    private func processPayment() {
        // 检查登录
        guard appState.isLoggedIn else {
            showLoginAlert = true
            return
        }

        isLoading = true
        Task {
            do {
                // 1. 创建订单
                let purchaseResp = try await APIClient.shared.purchaseCert(
                    udid: udid,
                    productType: "personal_cert"
                )
                guard let orderData = purchaseResp.data else {
                    await MainActor.run {
                        isLoading = false
                        paymentError = purchaseResp.error ?? "创建订单失败"
                        showPaymentError = true
                    }
                    return
                }

                // 2. 创建支付宝支付
                let payResp = try await APIClient.shared.createAlipayPayment(orderNo: orderData.orderNo)
                guard let payData = payResp.data, let payURL = URL(string: payData.paymentURL) else {
                    await MainActor.run {
                        isLoading = false
                        paymentError = payResp.error ?? "获取支付链接失败"
                        showPaymentError = true
                    }
                    return
                }

                // 持久化 orderNo：App 若被挂起/杀掉，回来后仍能恢复订单状态
                UserDefaults.standard.set(orderData.orderNo, forKey: Self.pendingOrderKey)
                await MainActor.run {
                    pendingOrderNo = orderData.orderNo
                    UIApplication.shared.open(payURL)
                    step = .generating
                    isLoading = false
                }

                // 开始状态轮询
                startOrderPolling(orderNo: orderData.orderNo)
            } catch {
                await MainActor.run {
                    isLoading = false
                    paymentError = "支付失败: \(error.localizedDescription)"
                    showPaymentError = true
                }
            }
        }
    }

    /// 轮询订单支付状态 + 证书生成（支付成功后服务端会自动生成，这里只负责取回文件）
    private func startOrderPolling(orderNo: String) {
        pollingTask?.cancel()
        pollingTask = Task {
            for _ in 0..<100 { // 最多 5 分钟（3s × 100）
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }

                // 先查订单状态（不直接打扰证书接口）
                do {
                    let orders = try await APIClient.shared.getOrders()
                    let order = orders.data?.first(where: { $0.orderNo == orderNo })
                    guard let order = order else { continue }
                    guard order.paymentStatus == "paid" else { continue }

                    // 已支付 → 尝试取回证书（服务端按 orderNo 幂等，有就直接返回）
                    let certResp = try await APIClient.shared.generateCert(orderNo: orderNo, udid: udid)
                    if let certData = certResp.data {
                        _ = try? CertStorage.shared.saveCert(
                            batchNo: certData.udidBatchNo,
                            p12Base64: certData.p12Data,
                            mobileprovisionBase64: certData.mobileprovisionData
                        )
                        await MainActor.run {
                            UserDefaults.standard.removeObject(forKey: Self.pendingOrderKey)
                            pendingOrderNo = ""
                            step = .complete
                        }
                        return
                    }
                } catch {
                    // 网络错误继续重试
                    continue
                }
            }
            await MainActor.run {
                paymentError = "证书生成超时，请稍后在证书列表中查看"
                showPaymentError = true
            }
        }
    }

    /// 恢复 pending 订单（App 被挂起或重新打开时调用）
    private func resumePendingOrder() {
        guard pendingOrderNo.isEmpty,
              let saved = UserDefaults.standard.string(forKey: Self.pendingOrderKey),
              !saved.isEmpty else { return }

        pendingOrderNo = saved
        if step != .complete {
            step = .generating
        }
        // 预填 UDID（如果已获取）
        if udid.isEmpty {
            autoLoadUDID()
        }
        startOrderPolling(orderNo: saved)
    }

    /// 清理所有计时器 / Task，避免页面消失后仍占用网络
    private func cleanupTimers() {
        udidCheckTimer?.invalidate()
        udidCheckTimer = nil
        pollingTask?.cancel()
        pollingTask = nil
    }
}

// MARK: - 步骤指示器组件

struct StepDot: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isDone: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : (isActive ? Color.jsPrimary : Color(.systemGray4)))
                    .frame(width: 28, height: 28)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }
            Text(title)
                .font(.caption2)
                .foregroundColor(isActive || isDone ? .primary : .secondary)
        }
    }
}

struct StepLine: View {
    let isDone: Bool

    var body: some View {
        Rectangle()
            .fill(isDone ? Color.green : Color(.systemGray4))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
    }
}
