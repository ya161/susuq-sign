import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct IPAListView: View {
    @State private var ipaFiles: [StoredIPA] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    @State private var successCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if ipaFiles.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("暂无 IPA 文件")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("通过文件 App 导入 IPA，或从 Safari 下载")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            openFilePicker()
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("导入 IPA")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.jsPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Text("已用空间")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(IPAParser.formatFileSize(IPAStorage.shared.totalStorageSize()))
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                        }

                        Section("已导入") {
                            ForEach(ipaFiles) { ipa in
                                IPARow(ipa: ipa)
                            }
                            .onDelete { indexSet in
                                deleteIPAs(at: indexSet)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("IPA 文件")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openFilePicker()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear { loadIPAs() }
            .alert("导入失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("导入成功", isPresented: $showSuccess) {
                Button("确定") {}
            } message: {
                Text("成功导入 \(successCount) 个 IPA 文件")
            }
        }
    }

    private func loadIPAs() {
        ipaFiles = IPAStorage.shared.listIPAs()
        // 对 info 为 nil 的 IPA 在后台异步解析
        for ipa in ipaFiles where ipa.info == nil {
            parseIPAInBackground(ipa: ipa)
        }
    }

    /// 后台异步解析 IPA 信息，完成后更新列表和缓存
    private func parseIPAInBackground(ipa: StoredIPA) {
        Task.detached(priority: .utility) {
            guard let info = try? IPAParser.shared.parse(ipaURL: ipa.filePath) else { return }
            // 写入缓存
            IPAStorage.shared.updateIPACache(id: ipa.id, info: info)
            // 更新 UI
            await MainActor.run {
                if let index = ipaFiles.firstIndex(where: { $0.id == ipa.id }) {
                    ipaFiles[index] = StoredIPA(
                        id: ipa.id,
                        fileName: ipa.fileName,
                        filePath: ipa.filePath,
                        importDate: ipa.importDate,
                        fileSize: ipa.fileSize,
                        info: info
                    )
                }
            }
        }
    }

    /// 直接从 UIKit 层弹出文档选择器，避免 SwiftUI sheet/fileImporter 的兼容问题
    private func openFilePicker() {
        let types: [UTType] = [.data, .item, .archive]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        let delegate = FilePickerDelegate { [self] urls in
            handleImportedURLs(urls)
        }
        // 用 objc_setAssociatedObject 防止 delegate 被释放
        objc_setAssociatedObject(picker, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        picker.delegate = delegate

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(picker, animated: true)
    }

    private func handleImportedURLs(_ urls: [URL]) {
        let ipaURLs = urls.filter { $0.pathExtension.lowercased() == "ipa" }
        if ipaURLs.isEmpty {
            errorMessage = "请选择 .ipa 格式的文件"
            showError = true
            return
        }
        var imported = 0
        var lastError: String?
        for url in ipaURLs {
            do {
                let stored = try IPAStorage.shared.importIPA(from: url)
                ipaFiles.insert(stored, at: 0)
                imported += 1
                // 异步解析新导入的 IPA 信息
                parseIPAInBackground(ipa: stored)
            } catch {
                lastError = error.localizedDescription
            }
        }
        if imported > 0 {
            successCount = imported
            showSuccess = true
        } else if let err = lastError {
            errorMessage = err
            showError = true
        }
    }

    private func deleteIPAs(at offsets: IndexSet) {
        for index in offsets {
            let ipa = ipaFiles[index]
            try? IPAStorage.shared.deleteIPA(id: ipa.id)
        }
        ipaFiles.remove(atOffsets: offsets)
    }
}

// MARK: - UIDocumentPicker Delegate（直接用 UIKit 弹出，不经过 SwiftUI sheet）

class FilePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]) -> Void

    init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消，不做任何事
    }
}

// MARK: - IPA 行

struct IPARow: View {
    let ipa: StoredIPA

    var body: some View {
        HStack(spacing: 12) {
            if let icon = ipa.info?.icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .cornerRadius(10)
            } else {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundColor(.jsPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.jsPrimary.opacity(0.1))
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 3) {
                // App 真实名称（从 IPA 内 Info.plist 读取）
                Text(ipa.info?.displayName ?? ipa.fileName.replacingOccurrences(of: ".ipa", with: ""))
                    .fontWeight(.medium)
                    .lineLimit(1)
                // IPA 文件名（小字）
                if ipa.info?.displayName != nil {
                    Text(ipa.fileName)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
                Text(ipa.info?.bundleIdentifier ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let info = ipa.info {
                        Text("v\(info.shortVersion)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(ipa.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
