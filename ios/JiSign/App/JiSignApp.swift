import SwiftUI

@main
struct JiSignApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(updateChecker)
                .onAppear {
                    restoreLoginState()
                    updateChecker.checkForUpdate()
                }
                .onReceive(NotificationCenter.default.publisher(for: .jiSignUnauthorized)) { _ in
                    // 后端返回 401 → 自动退登
                    appState.logout()
                }
        }
    }

    /// 启动时恢复登录状态（APIClient 内部已按 JWT exp 过滤过期 token）
    private func restoreLoginState() {
        guard APIClient.shared.isAuthenticated,
              let user = APIClient.loadUser() else { return }
        appState.currentUser = AppState.User(
            id: user.id,
            phone: user.phone,
            nickname: user.nickname
        )
        appState.isLoggedIn = true

        // 后台静默预取 UDID 签名令牌，供后续 UDID 流程使用
        Task { _ = try? await APIClient.shared.getUdidSign() }
    }
}

/// 全局应用状态
class AppState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var currentUser: User?

    struct User {
        let id: Int64
        let phone: String
        let nickname: String
    }

    /// 退出登录
    func logout() {
        isLoggedIn = false
        currentUser = nil
        APIClient.shared.clearAuth()
    }
}
