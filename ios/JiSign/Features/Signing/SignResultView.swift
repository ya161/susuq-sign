import SwiftUI
import UIKit

/// 签名完成结果页 — 终端风格日志 + 本地安装 + 导出
struct SignResultView: View {
    let signedIPAPath: URL?
    let allSignedIPAs: [(path: URL, bundleID: String)]
    let originalIPAPath: URL?
    let appName: String
    let bundleID: String
    let signedCount: Int
    var realSignLogs: [String] = []  // 实际签名过程的日志

    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var terminalLogs: [TerminalLog] = []
    @State private var uploadProgress: Double = 0
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                terminalView
                if isInstalling && uploadProgress > 0 {
                    uploadProgressView
                }
                buttonsView
            }
            .navigationTitle("签名结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        LocalIPAServer.shared.stop()
                        dismiss()
                    }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("确定") {}
            } message: {
                Text(alertMessage)
            }
            .onAppear { showSignLogs() }
        }
    }

    // MARK: - 子视图

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("签名成功")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(appName.isEmpty ? "已签名 \(signedCount) 个应用" : appName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(fileSizeText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(6)
        }
        .padding()
    }

    private var fileSizeText: String {
        guard let path = signedIPAPath else { return "" }
        let size = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int64) ?? 0
        return IPAParser.formatFileSize(size)
    }

    private var terminalView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(terminalLogs) { log in
                        TerminalLogRow(log: log)
                    }
                    if isInstalling {
                        cursorRow
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(12)
            .padding(.horizontal)
            .onChange(of: terminalLogs.count) { _ in
                withAnimation {
                    if let lastID = terminalLogs.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var cursorRow: some View {
        HStack(spacing: 6) {
            Text(currentTime())
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.4))
            Text("▌")
                .foregroundColor(.green)
                .opacity(0.8)
        }
        .font(.system(size: 12, design: .monospaced))
        .id("cursor")
    }

    private var uploadProgressView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("上传进度")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(uploadProgress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.jsPrimary)
            }
            ProgressView(value: uploadProgress)
                .tint(.jsPrimary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var buttonsView: some View {
        VStack(spacing: 10) {
            Button { installLocally() } label: {
                HStack(spacing: 8) {
                    if isInstalling {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.app.fill")
                    }
                    Text(isInstalling ? "安装中..." : "安装到本机")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(isInstalling ? Color.gray : Color.jsPrimary)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(isInstalling || signedIPAPath == nil)

            Button { exportIPA() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出 IPA").fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(.systemGray6))
                .foregroundColor(.jsPrimary)
                .cornerRadius(14)
            }
            .disabled(signedIPAPath == nil)
        }
        .padding()
    }

    // MARK: - 签名日志（签名已完成，展示回顾）

    private func showSignLogs() {
        // 显示签名过程的真实日志
        if realSignLogs.isEmpty {
            appendLog("签名完成（无详细日志）", isSuccess: true, isError: false)
            return
        }
        for (i, log) in realSignLogs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                let isSuccess = log.contains("✓") || log.contains("✅")
                let isError = log.contains("❌") || log.contains("⚠")
                appendLog(log, isSuccess: isSuccess, isError: isError)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(realSignLogs.count) * 0.08) {
            appendLog("✅ 签名完成!", isSuccess: true, isError: false)
        }
    }

    // MARK: - 本地 HTTPS 安装（零上传，和全能签相同方案）

    @State private var currentInstallIndex = 0

    private func installLocally() {
        // 构建安装列表：使用每个 IPA 的实际 bundle ID
        var installList: [(path: URL, bid: String)] = []
        if !allSignedIPAs.isEmpty {
            installList = allSignedIPAs.map { ($0.path, $0.bundleID) }
        } else if let path = signedIPAPath {
            installList = [(path, bundleID)]
        }
        guard !installList.isEmpty else { return }
        isInstalling = true
        currentInstallIndex = 0

        let total = installList.count
        if total > 1 {
            appendLog("共 \(total) 个应用需要安装", isSuccess: false, isError: false)
        }
        let name = appName.isEmpty ? "签名应用" : appName

        Task {
            let _ = await LocalIPAServer.downloadLatestCert()

            for (i, item) in installList.enumerated() {
                currentInstallIndex = i
                let bid = item.bid

                await MainActor.run {
                    if total > 1 { appendLog("安装 \(i+1)/\(total)...", isSuccess: false, isError: false) }
                }

                // 启动本地 HTTPS 服务器
                let startResult = await withCheckedContinuation { (cont: CheckedContinuation<Result<UInt16, Error>, Never>) in
                    LocalIPAServer.shared.start(ipaPath: item.path.path, bundleID: bid, appName: name) { result in
                        cont.resume(returning: result)
                    }
                }

                switch startResult {
                case .success(let port):
                    let installURL = LocalIPAServer.shared.getInstallURL()
                    await MainActor.run {
                        appendLog("✅ HTTPS 就绪 (:\(port))", isSuccess: true, isError: false)
                        if let url = URL(string: installURL) {
                            UIApplication.shared.open(url)
                        }
                        appendLog("请在弹窗中点击「安装」", isSuccess: false, isError: false)
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000_000)

                case .failure(let error):
                    await MainActor.run {
                        appendLog("❌ HTTPS 失败: \(error.localizedDescription)", isSuccess: false, isError: true)
                    }
                    continue
                }
            }

            await MainActor.run {
                isInstalling = false
                appendLog("✅ 全部完成，返回桌面查看", isSuccess: true, isError: false)
            }
        }
    }

    /// 备用：上传到服务器安装
    private func fallbackServerInstall() {
        guard let ipaPath = originalIPAPath ?? signedIPAPath else { isInstalling = false; return }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: ipaPath.path)[.size] as? Int64) ?? 0
        appendLog("上传 IPA (\(IPAParser.formatFileSize(fileSize)))...", isSuccess: false, isError: false)
        uploadProgress = 0

        Task {
            do {
                let resp = try await APIClient.shared.remoteSignAndInstall(
                    ipaURL: ipaPath, bundleID: bundleID, appName: appName
                ) { pct in uploadProgress = pct }

                guard let data = resp.data, let url = URL(string: data.installURL) else {
                    await MainActor.run {
                        appendLog("❌ \(resp.error ?? "失败")", isSuccess: false, isError: true)
                        isInstalling = false
                    }
                    return
                }
                await MainActor.run {
                    appendLog("✅ 上传完成", isSuccess: true, isError: false)
                    UIApplication.shared.open(url)
                    isInstalling = false
                    appendLog("✅ 请在弹窗中点击「安装」", isSuccess: true, isError: false)
                }
            } catch {
                await MainActor.run {
                    appendLog("❌ \(error.localizedDescription)", isSuccess: false, isError: true)
                    isInstalling = false
                }
            }
        }
    }

    // MARK: - 导出

    private func exportIPA() {
        guard let ipaPath = signedIPAPath else { return }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let activityVC = UIActivityViewController(activityItems: [ipaPath], applicationActivities: nil)
        top.present(activityVC, animated: true)
    }

    // MARK: - 日志工具

    private func appendLog(_ message: String, isSuccess: Bool, isError: Bool) {
        terminalLogs.append(TerminalLog(time: currentTime(), message: message, isSuccess: isSuccess, isError: isError))
    }

    private func currentTime() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return "[\(fmt.string(from: Date()))]"
    }
}

// MARK: - 终端日志行

struct TerminalLogRow: View {
    let log: TerminalLog
    private let greenColor = Color(red: 0.4, green: 0.8, blue: 0.4)
    private let grayColor = Color(red: 0.8, green: 0.8, blue: 0.8)

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(log.time)
                .foregroundColor(greenColor)
            Text(log.message)
                .foregroundColor(log.isError ? .red : (log.isSuccess ? .green : grayColor))
        }
        .font(.system(size: 12, design: .monospaced))
        .id(log.id)
    }
}

// MARK: - 终端日志模型

struct TerminalLog: Identifiable {
    let id = UUID()
    let time: String
    let message: String
    let isSuccess: Bool
    let isError: Bool
}
