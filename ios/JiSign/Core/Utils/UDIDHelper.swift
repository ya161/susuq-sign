import Foundation
import UIKit

/// UDID 获取辅助工具
/// 通过 Safari 跳转到后端的 mobileconfig 页面来获取设备 UDID
///
/// 流程说明：
/// 1. 打开 Safari 跳转到后端提供的 mobileconfig 下载页
/// 2. 用户安装描述文件后，系统会将 UDID 回传到后端
/// 3. 后端记录 UDID 并通过回调通知 App
class UDIDHelper {
    static let shared = UDIDHelper()

    private init() {}

    // MARK: - 公开方法

    /// 打开 Safari 跳转到 UDID 获取页面
    /// - Parameters:
    ///   - userID: 用户 ID，用于关联 UDID 与用户
    ///   - baseURL: 后端服务器地址（如 https://api.susuq.top）
    func openUDIDCollection(userID: String, baseURL: String) {
        // 构建获取 UDID 的 URL
        // 后端会返回一个 mobileconfig 描述文件，安装后回传 UDID
        let udidURL = buildUDIDURL(userID: userID, baseURL: baseURL)

        guard let url = URL(string: udidURL) else {
            print("[UDIDHelper] URL 构建失败: \(udidURL)")
            return
        }

        // 在主线程打开 Safari
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    print("[UDIDHelper] 已打开 Safari 获取 UDID")
                } else {
                    print("[UDIDHelper] 打开 Safari 失败")
                }
            }
        }
    }

    /// 构建 UDID 获取页面的 URL
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - baseURL: 后端服务器地址
    /// - Returns: 完整的 UDID 获取 URL
    func buildUDIDURL(userID: String, baseURL: String) -> String {
        // 添加时间戳防止缓存
        let timestamp = Int(Date().timeIntervalSince1970)
        // URL 编码用户 ID
        let encodedUserID = userID.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? userID

        return "\(baseURL)/api/udid/config?user_id=\(encodedUserID)&t=\(timestamp)"
    }

    /// 检查是否已获取 UDID（通过 API 查询后端）
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - baseURL: 后端服务器地址
    /// - Returns: 已获取的 UDID，如果未获取则返回 nil
    func checkUDID(userID: String, baseURL: String) async throws -> String? {
        let urlString = "\(baseURL)/api/udid/check?user_id=\(userID)"
        guard let url = URL(string: urlString) else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        struct UDIDResponse: Decodable {
            let success: Bool
            let data: UDIDData?

            struct UDIDData: Decodable {
                let udid: String?
            }
        }

        let response = try JSONDecoder().decode(UDIDResponse.self, from: data)
        return response.data?.udid
    }

    /// 生成 UDID 获取的深链接 URL Scheme
    /// 用于从 Safari 回调到 App
    /// - Parameter udid: 获取到的 UDID
    /// - Returns: App 的 URL Scheme 链接
    static func buildCallbackURL(udid: String) -> String {
        return "jisign://udid?value=\(udid)"
    }
}
