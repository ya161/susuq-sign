import SwiftUI

// MARK: - 软件源模型

struct AppSource: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let iconURL: String?
    var ipaCount: Int
    var isBuiltIn: Bool = false
}

// MARK: - 软件源列表视图

struct SourceListView: View {
    @State private var sources: [AppSource] = []
    @State private var showAddSheet = false
    @State private var newSourceURL = ""
    @State private var isLoadingSource = false

    var body: some View {
        Group {
            if sources.isEmpty {
                emptyStateView
            } else {
                sourceListContent
            }
        }
        .navigationTitle("软件源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addSourceSheet
        }
        .onAppear {
            if sources.isEmpty {
                loadBuiltInSources()
            }
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无软件源")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("添加软件源后即可浏览和下载 IPA")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))

            Button {
                loadBuiltInSources()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("加载推荐源")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.jsPrimary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - 源列表

    private var sourceListContent: some View {
        List {
            Section("推荐源") {
                ForEach(sources.filter { $0.isBuiltIn }) { source in
                    NavigationLink {
                        SourceBrowseView(source: source)
                    } label: {
                        SourceRow(source: source)
                    }
                }
            }

            let customSources = sources.filter { !$0.isBuiltIn }
            if !customSources.isEmpty {
                Section("自定义源") {
                    ForEach(customSources) { source in
                        NavigationLink {
                            SourceBrowseView(source: source)
                        } label: {
                            SourceRow(source: source)
                        }
                    }
                    .onDelete { indexSet in
                        let custom = sources.filter { !$0.isBuiltIn }
                        let idsToRemove = indexSet.map { custom[$0].id }
                        sources.removeAll { idsToRemove.contains($0.id) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 添加源弹窗

    private var addSourceSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 50))
                    .foregroundColor(.jsPrimary)

                Text("添加软件源")
                    .font(.title2)
                    .fontWeight(.bold)

                TextField("输入源地址 (URL)", text: $newSourceURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                Button {
                    addSource()
                } label: {
                    HStack {
                        if isLoadingSource {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isLoadingSource ? "验证中..." : "添加")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(newSourceURL.isEmpty ? Color.gray : Color.jsPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(newSourceURL.isEmpty || isLoadingSource)

                Spacer()
            }
            .padding()
            .navigationTitle("添加源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 内置推荐源

    private func loadBuiltInSources() {
        sources = [
            AppSource(name: "速签精选", url: "https://source.susuq.com", iconURL: nil, ipaCount: 128, isBuiltIn: true),
            AppSource(name: "App 多开源", url: "https://duokai.susuq.com", iconURL: nil, ipaCount: 45, isBuiltIn: true),
            AppSource(name: "插件工具源", url: "https://plugins.susuq.com", iconURL: nil, ipaCount: 67, isBuiltIn: true),
        ]
    }

    // MARK: - 添加自定义源

    private func addSource() {
        guard !newSourceURL.isEmpty else { return }
        isLoadingSource = true
        // TODO: 验证 URL、拉取源信息
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let source = AppSource(
                name: "自定义源",
                url: newSourceURL,
                iconURL: nil,
                ipaCount: 0,
                isBuiltIn: false
            )
            sources.append(source)
            isLoadingSource = false
            newSourceURL = ""
            showAddSheet = false
        }
    }
}

// MARK: - 源列表行

struct SourceRow: View {
    let source: AppSource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.title3)
                .foregroundColor(.jsPrimary)
                .frame(width: 40, height: 40)
                .background(Color.jsPrimary.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .fontWeight(.medium)
                Text(source.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(source.ipaCount) 个")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(6)
        }
        .padding(.vertical, 2)
    }
}
