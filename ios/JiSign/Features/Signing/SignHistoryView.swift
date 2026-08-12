import SwiftUI

// MARK: - 签名历史记录模型

struct SignRecord: Identifiable {
    let id = UUID()
    let appName: String
    let bundleID: String
    let signDate: Date
    let status: SignStatus
    let ipaPath: URL?
    let iconName: String

    enum SignStatus: String {
        case success = "成功"
        case failed = "失败"
        case expired = "已过期"

        var color: Color {
            switch self {
            case .success: return .green
            case .failed: return .red
            case .expired: return .orange
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .expired: return "clock.badge.exclamationmark"
            }
        }
    }
}

// MARK: - 签名历史视图

struct SignHistoryView: View {
    @State private var records: [SignRecord] = []
    @State private var showingInstallAlert = false
    @State private var selectedRecord: SignRecord?

    var body: some View {
        Group {
            if records.isEmpty {
                emptyStateView
            } else {
                recordListView
            }
        }
        .navigationTitle("签名记录")
        .alert("安装确认", isPresented: $showingInstallAlert) {
            Button("安装", role: .none) {
                if let record = selectedRecord {
                    reinstallIPA(record)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("是否重新安装「\(selectedRecord?.appName ?? "")」？")
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无签名记录")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("完成一次签名后，记录会显示在这里")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - 记录列表

    private var recordListView: some View {
        List {
            ForEach(records) { record in
                SignRecordRow(record: record) {
                    selectedRecord = record
                    showingInstallAlert = true
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 重新安装

    private func reinstallIPA(_ record: SignRecord) {
        // TODO: 调用 itms-services 协议安装已签名 IPA
        // 例如: UIApplication.shared.open(installURL)
    }
}

// MARK: - 签名记录行

struct SignRecordRow: View {
    let record: SignRecord
    let onReinstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App 图标
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundColor(.jsPrimary)
                .frame(width: 44, height: 44)
                .background(Color.jsPrimary.opacity(0.1))
                .cornerRadius(10)

            // 信息
            VStack(alignment: .leading, spacing: 3) {
                Text(record.appName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(record.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: record.status.icon)
                        .font(.caption2)
                        .foregroundColor(record.status.color)
                    Text(record.status.rawValue)
                        .font(.caption2)
                        .foregroundColor(record.status.color)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(record.signDate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 重新安装按钮
            if record.status == .success, record.ipaPath != nil {
                Button {
                    onReinstall()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.jsPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
