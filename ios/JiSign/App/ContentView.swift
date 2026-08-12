import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var selectedTab = 0
    @State private var showUpdateAlert = false
    @State private var updateError: String?
    @State private var hasShownUpdateAlert = false

    var body: some View {
        TabView(selection: $selectedTab) {
            SigningView()
                .tabItem {
                    Image(systemName: "signature")
                    Text("签名")
                }
                .tag(0)

            CertStoreView()
                .tabItem {
                    Image(systemName: "shield.checkered")
                    Text("证书")
                }
                .tag(1)

            IPAListView()
                .tabItem {
                    Image(systemName: "doc.zipper")
                    Text("IPA")
                }
                .tag(2)

            DiscoverView()
                .tabItem {
                    Image(systemName: "safari")
                    Text("发现")
                }
                .tag(3)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("我的")
                }
                .tag(4)
        }
        .tint(.jsPrimary)
        .onChange(of: updateChecker.hasUpdate) { hasUpdate in
            if hasUpdate && !hasShownUpdateAlert {
                hasShownUpdateAlert = true
                showUpdateAlert = true
            }
        }
        .alert("发现新版本", isPresented: $showUpdateAlert) {
            if updateChecker.isForceUpdate {
                Button("立即更新") { triggerUpdate() }
            } else {
                Button("稍后再说", role: .cancel) {
                    updateChecker.hasUpdate = false
                }
                Button("立即更新") { triggerUpdate() }
            }
        } message: {
            Text("v\(updateChecker.latestVersion) 已发布\n\(updateChecker.updateNote)")
        }
        .alert("更新失败", isPresented: .init(
            get: { updateError != nil },
            set: { if !$0 { updateError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(updateError ?? "")
        }
    }

    private func triggerUpdate() {
        if !appState.isLoggedIn {
            updateError = "请先登录账号，再更新 App"
            return
        }
        Task {
            if let error = await updateChecker.performUpdate() {
                await MainActor.run { updateError = error }
            }
        }
    }
}
