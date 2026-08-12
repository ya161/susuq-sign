import SwiftUI

// MARK: - 关于页面

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // MARK: - App 图标和信息
                VStack(spacing: 12) {
                    Image(systemName: "signature")
                        .font(.system(size: 60))
                        .foregroundColor(.jsPrimary)
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color.jsPrimary.opacity(0.1))
                        )

                    Text("速签")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("版本 \(appVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                // MARK: - 功能介绍
                VStack(alignment: .leading, spacing: 0) {
                    AboutFeatureItem(
                        icon: "signature",
                        title: "IPA 签名",
                        description: "使用个人证书签名任意 IPA 文件",
                        isLast: false
                    )
                    AboutFeatureItem(
                        icon: "app.badge.checkmark",
                        title: "多开分身",
                        description: "修改 Bundle ID 实现 App 多开",
                        isLast: false
                    )
                    AboutFeatureItem(
                        icon: "puzzlepiece.extension",
                        title: "插件注入",
                        description: "注入 dylib 动态库增强功能",
                        isLast: false
                    )
                    AboutFeatureItem(
                        icon: "externaldrive",
                        title: "软件源",
                        description: "丰富的 IPA 资源，一键下载签名",
                        isLast: false
                    )
                    AboutFeatureItem(
                        icon: "globe",
                        title: "内置浏览器",
                        description: "浏览网页并自动拦截 IPA 下载",
                        isLast: true
                    )
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // MARK: - 联系和链接
                VStack(spacing: 0) {
                    AboutLinkItem(
                        icon: "message.fill",
                        title: "联系客服",
                        color: .jsPrimary
                    ) {
                        // TODO: 打开客服对话
                    }
                    Divider().padding(.leading, 52)
                    AboutLinkItem(
                        icon: "envelope.fill",
                        title: "意见反馈",
                        color: .blue
                    ) {
                        // TODO: 打开反馈页面
                    }
                    Divider().padding(.leading, 52)
                    AboutLinkItem(
                        icon: "doc.text.fill",
                        title: "用户协议",
                        color: .secondary
                    ) {
                        // TODO: 打开用户协议
                    }
                    Divider().padding(.leading, 52)
                    AboutLinkItem(
                        icon: "hand.raised.fill",
                        title: "隐私政策",
                        color: .secondary
                    ) {
                        // TODO: 打开隐私政策
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // MARK: - 版权信息
                VStack(spacing: 4) {
                    Text("速签 SuSign")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Copyright © 2026 速签团队")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
        .navigationTitle("关于速签")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - App 版本号

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - 功能介绍行

struct AboutFeatureItem: View {
    let icon: String
    let title: String
    let description: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.jsPrimary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !isLast {
                Divider().padding(.leading, 62)
            }
        }
    }
}

// MARK: - 链接行

struct AboutLinkItem: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(color)
                    .frame(width: 32)

                Text(title)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }
}
