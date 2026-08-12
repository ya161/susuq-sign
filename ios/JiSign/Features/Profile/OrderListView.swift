import SwiftUI

// MARK: - 订单模型

struct Order: Identifiable {
    let id = UUID()
    let orderNo: String
    let certType: String
    let amount: Double
    let createDate: Date
    let status: OrderStatus

    enum OrderStatus: String {
        case paid = "已支付"
        case pending = "待支付"
        case refunded = "已退款"
        case cancelled = "已取消"
        case closed = "已关闭"

        var color: Color {
            switch self {
            case .paid: return .green
            case .pending: return .orange
            case .refunded: return .blue
            case .cancelled, .closed: return .secondary
            }
        }

        var icon: String {
            switch self {
            case .paid: return "checkmark.circle.fill"
            case .pending: return "clock.fill"
            case .refunded: return "arrow.uturn.left.circle.fill"
            case .cancelled, .closed: return "xmark.circle.fill"
            }
        }

        static func from(_ raw: String) -> OrderStatus {
            switch raw {
            case "paid": return .paid
            case "pending": return .pending
            case "refunded": return .refunded
            case "closed": return .closed
            default: return .cancelled
            }
        }
    }
}

// MARK: - 订单列表视图

struct OrderListView: View {
    @State private var orders: [Order] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && orders.isEmpty {
                ProgressView("加载订单...")
            } else if orders.isEmpty {
                emptyStateView
            } else {
                orderList
            }
        }
        .navigationTitle("我的订单")
        .onAppear { loadOrders() }
        .refreshable { loadOrders() }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无订单")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("购买证书后，订单记录会显示在这里")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var orderList: some View {
        List {
            ForEach(orders) { order in
                OrderRow(order: order)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadOrders() {
        isLoading = true
        Task {
            do {
                let resp = try await APIClient.shared.getOrders()
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                await MainActor.run {
                    orders = resp.data?.map { data in
                        Order(
                            orderNo: data.orderNo,
                            certType: data.productType == "personal_cert" ? "个人开发者证书" : data.productType,
                            amount: data.amount,
                            createDate: dateFormatter.date(from: data.createdAt) ?? Date(),
                            status: Order.OrderStatus.from(data.paymentStatus)
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

// MARK: - 订单行

struct OrderRow: View {
    let order: Order

    private static let cnDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日 HH:mm"
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(order.certType)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: order.status.icon)
                        .font(.caption)
                    Text(order.status.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(order.status.color)
            }

            HStack {
                Text("订单号")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(order.orderNo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text("¥\(String(format: "%.2f", order.amount))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.0, green: 0.7, blue: 0.9))
                Spacer()
                Text(Self.cnDateFormatter.string(from: order.createDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
