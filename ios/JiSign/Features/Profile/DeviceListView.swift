import SwiftUI
import UIKit

// MARK: - 设备模型

struct BoundDevice: Identifiable {
    let id = UUID()
    let udid: String
    let model: String
    let bindDate: Date
    var isCurrentDevice: Bool = false
}

// MARK: - 设备列表视图

struct DeviceListView: View {
    @EnvironmentObject var appState: AppState
    @State private var devices: [BoundDevice] = []
    @State private var showAddDevice = false
    @State private var isLoading = false
    @State private var manualUDID = ""
    @State private var showManualInput = false

    var body: some View {
        Group {
            if isLoading && devices.isEmpty {
                ProgressView("加载设备...")
            } else if devices.isEmpty {
                emptyStateView
            } else {
                deviceList
            }
        }
        .navigationTitle("我的设备")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddDevice = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddDevice) {
            addDeviceSheet
        }
        .onAppear { loadDevices() }
        .refreshable { loadDevices() }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "iphone.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无绑定设备")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("绑定设备后即可使用签名功能")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
            Button {
                showAddDevice = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("添加设备")
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

    private var deviceList: some View {
        List {
            ForEach(devices) { device in
                DeviceRow(device: device)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var addDeviceSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "iphone.gen3.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.jsPrimary)

                Text("添加新设备")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("点击下方按钮将跳转至 Safari 安装描述文件，系统会自动获取设备的 UDID")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        collectUDID()
                    } label: {
                        HStack {
                            Image(systemName: "safari")
                            Text("获取 UDID")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.jsPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button {
                        showManualInput.toggle()
                    } label: {
                        Text("手动输入 UDID")
                            .font(.subheadline)
                            .foregroundColor(.jsPrimary)
                    }

                    if showManualInput {
                        VStack(spacing: 10) {
                            TextField("粘贴设备 UDID", text: $manualUDID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)

                            Button {
                                if !manualUDID.isEmpty {
                                    showAddDevice = false
                                    // UDID 会在购买证书时自动关联
                                }
                            } label: {
                                Text("确认")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(manualUDID.isEmpty ? Color.gray : Color.jsPrimary)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(manualUDID.isEmpty)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text("什么是 UDID？")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("UDID 是每台 Apple 设备的唯一标识符，签名证书需要绑定设备 UDID 才能正常使用。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
            .navigationTitle("添加设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showAddDevice = false }
                }
            }
        }
    }

    private func collectUDID() {
        let userID = appState.currentUser.map { String($0.id) } ?? "0"
        showAddDevice = false

        // 登录用户必须带 sig 才能通过服务端 HMAC 校验
        Task {
            if userID != "0", APIClient.shared.cachedUdidSig == nil {
                _ = try? await APIClient.shared.getUdidSign()
            }
            await MainActor.run {
                let urlStr = APIClient.shared.udidConfigURL(userID: userID)
                if let url = URL(string: urlStr) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func loadDevices() {
        isLoading = true
        Task {
            do {
                let resp = try await APIClient.shared.getDevices()
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                await MainActor.run {
                    devices = resp.data?.map { data in
                        BoundDevice(
                            udid: data.udid,
                            model: data.model.isEmpty ? "iPhone" : data.model,
                            bindDate: dateFormatter.date(from: data.createdAt) ?? Date()
                        )
                    } ?? []
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}

// MARK: - 设备行

struct DeviceRow: View {
    let device: BoundDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title2)
                .foregroundColor(.jsPrimary)
                .frame(width: 40, height: 40)
                .background(Color.jsPrimary.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(device.model)
                        .fontWeight(.medium)
                    if device.isCurrentDevice {
                        Text("本机")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.jsPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.jsPrimary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                Text(device.udid)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("绑定于 \(device.bindDate, style: .date)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
