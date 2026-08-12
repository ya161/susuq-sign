import SwiftUI

// MARK: - 自定义 Info.plist 键值对

struct PlistKeyValue: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

// MARK: - 高级签名选项视图

struct SignOptionsView: View {
    // 插件注入
    @State private var enableDylibInjection = false
    @State private var selectedDylibs: [URL] = []
    @State private var showDylibPicker = false

    // 修复选项
    @State private var removeSystemVersionLimit = false
    @State private var fixWhiteIcon = false
    @State private var enableFileSharingAccess = false

    // 自定义 Info.plist
    @State private var customPlistEntries: [PlistKeyValue] = []

    var body: some View {
        Form {
            // MARK: - 插件注入
            Section {
                Toggle(isOn: $enableDylibInjection) {
                    Label("启用插件注入", systemImage: "puzzlepiece.extension")
                }
                .tint(.jsPrimary)

                if enableDylibInjection {
                    // 已选择的 dylib 列表
                    ForEach(selectedDylibs, id: \.absoluteString) { url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.jsPrimary)
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                selectedDylibs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showDylibPicker = true
                    } label: {
                        Label("添加 dylib 文件", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("插件注入")
            } footer: {
                Text("将 dylib 动态库注入到 IPA 中，实现功能增强")
            }

            // MARK: - 修复选项
            Section {
                Toggle(isOn: $removeSystemVersionLimit) {
                    Label("移除系统版本限制", systemImage: "iphone.gen3.slash")
                }
                .tint(.jsPrimary)

                Toggle(isOn: $fixWhiteIcon) {
                    Label("修复白图标", systemImage: "app.dashed")
                }
                .tint(.jsPrimary)

                Toggle(isOn: $enableFileSharingAccess) {
                    Label("启用文件共享", systemImage: "folder.badge.person.crop")
                }
                .tint(.jsPrimary)
            } header: {
                Text("修复选项")
            } footer: {
                Text("移除系统版本限制可让 App 在旧版 iOS 上运行")
            }

            // MARK: - 自定义 Info.plist
            Section {
                ForEach($customPlistEntries) { $entry in
                    HStack(spacing: 8) {
                        TextField("Key", text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        TextField("Value", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        Button {
                            customPlistEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    customPlistEntries.append(PlistKeyValue(key: "", value: ""))
                } label: {
                    Label("添加键值对", systemImage: "plus.circle")
                }
            } header: {
                Text("自定义 Info.plist")
            } footer: {
                Text("添加或覆盖 Info.plist 中的键值对")
            }
        }
        .navigationTitle("高级选项")
        .fileImporter(
            isPresented: $showDylibPicker,
            allowedContentTypes: [.init(filenameExtension: "dylib")!],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    if !selectedDylibs.contains(url) {
                        selectedDylibs.append(url)
                    }
                }
            case .failure(let error):
                print("选择 dylib 失败: \(error)")
            }
        }
    }
}
