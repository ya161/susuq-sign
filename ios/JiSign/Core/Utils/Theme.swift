import SwiftUI

/// 速签全局主题色 — 蓝青渐变色系，与 Logo 一致
extension Color {
    /// 主色（蓝青色 #00B3E6）
    static let jsPrimary = Color(red: 0.0, green: 0.70, blue: 0.90)
    /// 深色（偏蓝 #0088CC）
    static let jsDeep = Color(red: 0.0, green: 0.53, blue: 0.80)
    /// 浅色（偏青 #33CCCC）
    static let jsLight = Color(red: 0.20, green: 0.80, blue: 0.80)
    /// 渐变
    static let jsGradient = LinearGradient(
        colors: [jsDeep, jsPrimary, jsLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
