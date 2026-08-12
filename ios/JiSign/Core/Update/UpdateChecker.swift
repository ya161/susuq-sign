import SwiftUI
import UIKit

/// App 更新检查器（优化版：检查时预加载安装链接，点更新秒跳转）
class UpdateChecker: ObservableObject {
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var updateNote = ""
    @Published var isForceUpdate = false
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var checkDone = false

    /// 预加载的安装 URL（检查版本时就获取，点更新时直接用）
    private var cachedInstallURL: URL?

    /// 检查是否有新版本（同时预加载安装链接）
    func checkForUpdate() {
        guard !isChecking else { return }
        isChecking = true
        checkDone = false

        Task {
            do {
                // 并行：检查版本 + 预加载安装链接
                async let versionCheck = APIClient.shared.checkVersion()
                async let updateURLFetch = APIClient.shared.getUpdateURL()

                let resp = try await versionCheck
                let updateResp = try? await updateURLFetch

                guard let data = resp.data else {
                    await MainActor.run { isChecking = false; checkDone = true }
                    return
                }

                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                let needsUpdate = compareVersion(current: currentVersion, latest: data.version)

                // 缓存安装 URL
                if let urlStr = updateResp?.data?.installURL, let url = URL(string: urlStr) {
                    cachedInstallURL = url
                }

                await MainActor.run {
                    isChecking = false
                    checkDone = true
                    if needsUpdate {
                        hasUpdate = true
                        latestVersion = data.version
                        updateNote = data.updateNote
                        isForceUpdate = data.force
                    }
                }
            } catch {
                await MainActor.run { isChecking = false; checkDone = true }
            }
        }
    }

    /// 执行更新（直接使用预加载的链接，秒跳转）
    func performUpdate() async -> String? {
        guard !isUpdating else { return nil }
        await MainActor.run { isUpdating = true }

        // 优先使用预加载的 URL
        if let url = cachedInstallURL {
            await MainActor.run {
                isUpdating = false
                hasUpdate = false
                UIApplication.shared.open(url)
            }
            return nil
        }

        // 兜底：实时获取
        do {
            let resp = try await APIClient.shared.getUpdateURL()
            guard let data = resp.data, let url = URL(string: data.installURL) else {
                await MainActor.run { isUpdating = false }
                return resp.error ?? "获取更新链接失败"
            }
            await MainActor.run {
                isUpdating = false
                hasUpdate = false
                UIApplication.shared.open(url)
            }
            return nil
        } catch {
            await MainActor.run { isUpdating = false }
            return "网络连接失败"
        }
    }

    /// 比较版本号
    private func compareVersion(current: String, latest: String) -> Bool {
        let c = current.split(separator: ".").compactMap { Int($0) }
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let count = max(c.count, l.count)
        for i in 0..<count {
            let cv = i < c.count ? c[i] : 0
            let lv = i < l.count ? l[i] : 0
            if cv < lv { return true }
            if cv > lv { return false }
        }
        return false
    }
}
