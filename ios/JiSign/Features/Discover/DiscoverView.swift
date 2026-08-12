import SwiftUI
import WebKit
import UIKit

// MARK: - 发现页面

struct DiscoverView: View {
    @State private var downloadURL = ""
    @State private var isDownloading = false
    @State private var showTutorial = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // IPA 下载入口
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .foregroundColor(.jsPrimary)
                            Text("IPA 下载")
                                .font(.headline)
                        }

                        Text("粘贴 IPA 文件的直链地址，直接下载到本地")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("粘贴 IPA 下载链接", text: $downloadURL)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .keyboardType(.URL)

                            Button {
                                startDownload()
                            } label: {
                                if isDownloading {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 60)
                                } else {
                                    Text("下载")
                                        .fontWeight(.medium)
                                        .frame(width: 60)
                                }
                            }
                            .padding(.vertical, 8)
                            .background(downloadURL.isEmpty ? Color.gray : Color.jsPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .disabled(downloadURL.isEmpty || isDownloading)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)

                    // IPA 获取方式
                    VStack(alignment: .leading, spacing: 12) {
                        Text("如何获取 IPA 文件？")
                            .font(.headline)

                        ImportMethodCard(
                            icon: "doc.badge.plus",
                            title: "文件导入",
                            desc: "从「文件」App 中选择 IPA 文件导入",
                            detail: "前往 IPA 页面，点击右上角 + 号导入"
                        )

                        ImportMethodCard(
                            icon: "wifi",
                            title: "AirDrop 接收",
                            desc: "从电脑或其他设备 AirDrop 传输 IPA",
                            detail: "收到的 IPA 文件会自动出现在速签中"
                        )

                        ImportMethodCard(
                            icon: "link",
                            title: "链接下载",
                            desc: "在上方粘贴 IPA 的直链地址下载",
                            detail: "支持任意 https 直链，下载后自动导入"
                        )

                        ImportMethodCard(
                            icon: "externaldrive.connected.to.line.below",
                            title: "网盘/云存储",
                            desc: "从百度网盘、iCloud 等云存储获取",
                            detail: "在网盘 App 中用速签打开 IPA 文件"
                        )

                        ImportMethodCard(
                            icon: "desktopcomputer",
                            title: "电脑端获取",
                            desc: "在电脑上下载 IPA 后传到手机",
                            detail: "推荐使用 AirDrop 或数据线传输"
                        )
                    }

                    // 签名能力一览
                    VStack(alignment: .leading, spacing: 12) {
                        Text("签名能力")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            FeatureCard(icon: "square.on.square", title: "应用多开", desc: "自动改 Bundle ID")
                            FeatureCard(icon: "textformat", title: "修改名称", desc: "自定义 App 名称")
                            FeatureCard(icon: "photo", title: "更换图标", desc: "自定义 App 图标")
                            FeatureCard(icon: "puzzlepiece", title: "注入插件", desc: "Dylib / Framework")
                            FeatureCard(icon: "lock.open", title: "移除限制", desc: "绕过版本限制")
                            FeatureCard(icon: "square.stack.3d.up", title: "批量签名", desc: "一次签多个 IPA")
                            FeatureCard(icon: "arrow.triangle.2.circlepath", title: "自动更新", desc: "App 内一键更新")
                            FeatureCard(icon: "shield.checkered", title: "证书管理", desc: "导入/导出证书")
                        }
                    }

                    // 使用提示
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("小贴士")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            TipRow(text: "签名后的 IPA 可以直接安装到本机")
                            TipRow(text: "多开同一个 App 需要修改 Bundle ID")
                            TipRow(text: "证书有效期约 1 年，到期需重新购买")
                            TipRow(text: "签名过程完全在本地完成，隐私安全")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }
                .padding()
            }
            .navigationTitle("发现")
        }
    }

    private func startDownload() {
        guard !downloadURL.isEmpty else { return }
        var urlStr = downloadURL
        if !urlStr.hasPrefix("http") {
            urlStr = "https://" + urlStr
        }
        guard let url = URL(string: urlStr) else { return }

        isDownloading = true

        Task {
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                let fileName = (response as? HTTPURLResponse)?.suggestedFilename
                    ?? url.lastPathComponent
                    ?? "download.ipa"

                let fm = FileManager.default
                let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destURL = docsDir.appendingPathComponent(fileName)
                try? fm.removeItem(at: destURL)
                try fm.moveItem(at: tempURL, to: destURL)

                // 导入到 IPA 存储
                try IPAStorage.shared.importIPA(from: destURL)
                try? fm.removeItem(at: destURL)

                await MainActor.run {
                    isDownloading = false
                    downloadURL = ""
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                }
            }
        }
    }
}

// MARK: - 导入方式卡片

struct ImportMethodCard: View {
    let icon: String
    let title: String
    let desc: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.jsPrimary)
                .frame(width: 40, height: 40)
                .background(Color.jsPrimary.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 小贴士行

struct TipRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 功能卡片

struct FeatureCard: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.jsPrimary)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Text(desc)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
