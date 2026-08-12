import SwiftUI

// MARK: - 内嵌框架/动态库信息

struct EmbeddedLibrary: Identifiable {
    let id = UUID()
    let name: String
    let type: LibraryType

    enum LibraryType: String {
        case dylib = "动态库"
        case framework = "Framework"

        var icon: String {
            switch self {
            case .dylib: return "puzzlepiece.extension"
            case .framework: return "shippingbox"
            }
        }
    }
}

// MARK: - IPA 详情视图

struct IPADetailView: View {
    let ipa: IPAFile

    @State private var embeddedLibraries: [EmbeddedLibrary] = []
    @State private var showDeleteAlert = false
    @State private var minimumOSVersion = "14.0"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - App 图标
                VStack(spacing: 12) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.jsPrimary)
                        .frame(width: 120, height: 120)
                        .background(Color.jsPrimary.opacity(0.1))
                        .cornerRadius(26)

                    Text(ipa.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // MARK: - 基本信息
                VStack(spacing: 0) {
                    InfoRow(label: "Bundle ID", value: ipa.bundleID)
                    Divider().padding(.leading, 16)
                    InfoRow(label: "版本", value: ipa.version)
                    Divider().padding(.leading, 16)
                    InfoRow(label: "文件大小", value: formattedSize)
                    Divider().padding(.leading, 16)
                    InfoRow(label: "最低系统版本", value: "iOS \(minimumOSVersion)")
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // MARK: - 内嵌库列表
                if !embeddedLibraries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("内嵌组件")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(embeddedLibraries.enumerated()), id: \.element.id) { index, lib in
                                HStack(spacing: 10) {
                                    Image(systemName: lib.type.icon)
                                        .foregroundColor(.jsPrimary)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lib.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(lib.type.rawValue)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                                if index < embeddedLibraries.count - 1 {
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }

                // MARK: - 操作按钮
                VStack(spacing: 12) {
                    Button {
                        signThisIPA()
                    } label: {
                        HStack {
                            Image(systemName: "signature")
                            Text("签名此 IPA")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.jsPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("删除文件")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .foregroundColor(.red)
                        .cornerRadius(14)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("IPA 详情")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                deleteIPA()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，确定要删除「\(ipa.name)」吗？")
        }
        .onAppear {
            loadIPADetails()
        }
    }

    // MARK: - 格式化文件大小

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: ipa.size)
    }

    // MARK: - 加载 IPA 详情

    private func loadIPADetails() {
        // TODO: 解析 IPA 内的 Frameworks 和 dylib
        // 示例数据
        embeddedLibraries = [
            EmbeddedLibrary(name: "libsubstrate.dylib", type: .dylib),
            EmbeddedLibrary(name: "RevealServer.framework", type: .framework),
        ]
    }

    private func signThisIPA() {
        // TODO: 跳转签名页面并预选此 IPA
    }

    private func deleteIPA() {
        // TODO: 删除 IPA 文件
        dismiss()
    }
}

// MARK: - 信息行

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
