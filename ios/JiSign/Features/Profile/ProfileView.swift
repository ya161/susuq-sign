import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var showLogin = false
    @State private var showUpdateError = false
    @State private var updateErrorMsg = ""

    var body: some View {
        NavigationStack {
            List {
                // 用户信息
                Section {
                    if appState.isLoggedIn {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.jsPrimary)
                            VStack(alignment: .leading) {
                                Text(appState.currentUser?.nickname ?? "用户")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                Text(appState.currentUser?.phone ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            showLogin = true
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("点击登录")
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // 功能入口
                Section("我的服务") {
                    NavigationLink {
                        OrderListView()
                    } label: {
                        Label("我的订单", systemImage: "list.bullet.rectangle")
                    }

                    NavigationLink {
                        SignHistoryView()
                    } label: {
                        Label("签名记录", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink {
                        DeviceListView()
                            .environmentObject(appState)
                    } label: {
                        Label("我的设备", systemImage: "iphone")
                    }
                }

                // 设置
                Section("设置") {
                    NavigationLink {
                        Text("通知设置")
                    } label: {
                        Label("通知管理", systemImage: "bell")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }

                    // 检查更新
                    Button {
                        if updateChecker.hasUpdate && !updateChecker.isUpdating {
                            if !appState.isLoggedIn {
                                updateErrorMsg = "请先登录账号，再更新 App"
                                showUpdateError = true
                                return
                            }
                            Task {
                                if let error = await updateChecker.performUpdate() {
                                    await MainActor.run {
                                        updateErrorMsg = error
                                        showUpdateError = true
                                    }
                                }
                            }
                        } else if !updateChecker.isChecking && !updateChecker.hasUpdate {
                            updateChecker.checkForUpdate()
                        }
                    } label: {
                        HStack {
                            Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if updateChecker.isChecking || updateChecker.isUpdating {
                                ProgressView()
                            } else if updateChecker.hasUpdate {
                                Text("v\(updateChecker.latestVersion) 可用")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(10)
                            } else if updateChecker.checkDone {
                                Text("已是最新")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("点击检查")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    .disabled(updateChecker.isChecking || updateChecker.isUpdating)

                    // 版本号
                    HStack {
                        Label("版本", systemImage: "number")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                // 联系客服
                Section {
                    Button {
                        // TODO: 联系客服
                    } label: {
                        Label("联系客服", systemImage: "message")
                    }
                }

                // 退出登录
                if appState.isLoggedIn {
                    Section {
                        Button(role: .destructive) {
                            appState.logout()
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(appState)
            }
            .alert("提示", isPresented: $showUpdateError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(updateErrorMsg)
            }
        }
    }
}
