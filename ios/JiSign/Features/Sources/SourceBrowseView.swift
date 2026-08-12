import SwiftUI

// MARK: - 源内 IPA 模型

struct SourceIPA: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let version: String
    let size: String
    let description: String
    let downloadURL: String
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
}

// MARK: - 浏览源内 IPA

struct SourceBrowseView: View {
    let source: AppSource

    @State private var ipas: [SourceIPA] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isGridMode = false

    private var filteredIPAs: [SourceIPA] {
        if searchText.isEmpty {
            return ipas
        }
        return ipas.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if filteredIPAs.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("未找到匹配的 App")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                if isGridMode {
                    gridView
                } else {
                    listView
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索 App")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { isGridMode.toggle() }
                } label: {
                    Image(systemName: isGridMode ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .onAppear {
            loadSourceIPAs()
        }
    }

    // MARK: - 列表视图

    private var listView: some View {
        List {
            ForEach(Array($ipas.enumerated()), id: \.element.id) { index, $ipa in
                let filtered = filteredIPAs
                if filtered.contains(where: { $0.id == ipa.id }) {
                    SourceIPAListRow(ipa: $ipa) {
                        downloadIPA(at: index)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 网格视图

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                ForEach(Array($ipas.enumerated()), id: \.element.id) { index, $ipa in
                    let filtered = filteredIPAs
                    if filtered.contains(where: { $0.id == ipa.id }) {
                        SourceIPAGridItem(ipa: $ipa) {
                            downloadIPA(at: index)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 下载 IPA

    private func downloadIPA(at index: Int) {
        guard index < ipas.count else { return }
        ipas[index].isDownloading = true
        // TODO: 实际下载逻辑
        // 模拟下载进度
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if index < ipas.count {
                ipas[index].downloadProgress += 0.05
                if ipas[index].downloadProgress >= 1.0 {
                    ipas[index].isDownloading = false
                    ipas[index].downloadProgress = 0
                    timer.invalidate()
                }
            } else {
                timer.invalidate()
            }
        }
    }

    // MARK: - 加载源数据

    private func loadSourceIPAs() {
        // TODO: 从源 URL 拉取 IPA 列表
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ipas = [
                SourceIPA(name: "微信", bundleID: "com.tencent.xin", version: "8.0.45", size: "268 MB", description: "微信多开版", downloadURL: ""),
                SourceIPA(name: "QQ", bundleID: "com.tencent.mqq", version: "9.0.70", size: "456 MB", description: "QQ 多开版", downloadURL: ""),
                SourceIPA(name: "抖音", bundleID: "com.ss.iphone.ugc.Aweme", version: "29.0", size: "380 MB", description: "抖音去水印版", downloadURL: ""),
                SourceIPA(name: "Telegram", bundleID: "ph.telegra.Telegraph", version: "10.8", size: "120 MB", description: "Telegram 中文版", downloadURL: ""),
                SourceIPA(name: "Instagram", bundleID: "com.burbn.instagram", version: "320.0", size: "210 MB", description: "Instagram Rocket", downloadURL: ""),
                SourceIPA(name: "YouTube", bundleID: "com.google.ios.youtube", version: "19.20", size: "310 MB", description: "YouTube 去广告版", downloadURL: ""),
            ]
            isLoading = false
        }
    }
}

// MARK: - 列表行

struct SourceIPAListRow: View {
    @Binding var ipa: SourceIPA
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundColor(.jsPrimary)
                .frame(width: 50, height: 50)
                .background(Color.jsPrimary.opacity(0.1))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 3) {
                Text(ipa.name)
                    .fontWeight(.medium)
                Text(ipa.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("v\(ipa.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ipa.size)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if ipa.isDownloading {
                VStack(spacing: 2) {
                    ProgressView(value: ipa.downloadProgress)
                        .frame(width: 50)
                        .tint(.jsPrimary)
                    Text("\(Int(ipa.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    onDownload()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.jsPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 网格项

struct SourceIPAGridItem: View {
    @Binding var ipa: SourceIPA
    let onDownload: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.fill")
                .font(.system(size: 40))
                .foregroundColor(.jsPrimary)
                .frame(width: 60, height: 60)
                .background(Color.jsPrimary.opacity(0.1))
                .cornerRadius(14)

            Text(ipa.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(ipa.size)
                .font(.caption2)
                .foregroundColor(.secondary)

            if ipa.isDownloading {
                ProgressView(value: ipa.downloadProgress)
                    .tint(.jsPrimary)
            } else {
                Button {
                    onDownload()
                } label: {
                    Text("下载")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(Color.jsPrimary.opacity(0.15))
                        .foregroundColor(.jsPrimary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}
