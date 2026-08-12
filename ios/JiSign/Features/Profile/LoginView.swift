import SwiftUI

// MARK: - 登录视图

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var isLoadingSMS = false
    @State private var isLoggingIn = false
    @State private var countdown = 0
    @State private var timer: Timer?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // MARK: - Logo 区域
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("速签")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("专业的 IPA 签名工具")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // MARK: - 输入区域
                VStack(spacing: 16) {
                    // 手机号
                    HStack(spacing: 12) {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.jsPrimary)
                            .frame(width: 24)
                        TextField("请输入手机号", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .font(.body)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // 验证码
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.jsPrimary)
                            .frame(width: 24)
                        TextField("请输入验证码", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .font(.body)

                        Button {
                            sendVerificationCode()
                        } label: {
                            Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(canSendSMS ? .jsPrimary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(canSendSMS ? Color.jsPrimary.opacity(0.1) : Color(.systemGray5))
                                .cornerRadius(8)
                        }
                        .disabled(!canSendSMS || isLoadingSMS)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 4)

                // MARK: - 登录按钮
                Button {
                    login()
                } label: {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isLoggingIn ? "登录中..." : "登录")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canLogin ? Color.jsPrimary : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(!canLogin || isLoggingIn)

                Spacer()

                // MARK: - 用户协议
                VStack(spacing: 8) {
                    Text("登录即表示同意")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Button {
                            // TODO: 打开用户协议
                        } label: {
                            Text("《用户协议》")
                                .font(.caption)
                                .foregroundColor(.jsPrimary)
                        }
                        Text("和")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            // TODO: 打开隐私政策
                        } label: {
                            Text("《隐私政策》")
                                .font(.caption)
                                .foregroundColor(.jsPrimary)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .alert("登录失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - 状态判断

    private var canSendSMS: Bool {
        phoneNumber.count == 11 && countdown == 0
    }

    private var canLogin: Bool {
        phoneNumber.count == 11 && verificationCode.count >= 4
    }

    // MARK: - 发送验证码

    private func sendVerificationCode() {
        isLoadingSMS = true
        Task {
            do {
                let resp = try await APIClient.shared.sendSMSCode(phone: phoneNumber)
                await MainActor.run {
                    if resp.success {
                        isLoadingSMS = false
                        countdown = 60
                        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                            countdown -= 1
                            if countdown <= 0 {
                                t.invalidate()
                                timer = nil
                            }
                        }
                    } else {
                        isLoadingSMS = false
                        errorMessage = resp.error ?? "验证码发送失败"
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingSMS = false
                    errorMessage = "网络连接失败，请检查网络后重试"
                    showError = true
                }
            }
        }
    }

    // MARK: - 登录

    private func login() {
        isLoggingIn = true
        Task {
            do {
                let loginResp = try await APIClient.shared.login(phone: phoneNumber, code: verificationCode)
                guard let loginData = loginResp.data else {
                    await MainActor.run {
                        isLoggingIn = false
                        errorMessage = loginResp.error ?? "登录失败"
                        showError = true
                    }
                    return
                }
                // 保存 token 和用户信息（token 入 Keychain，用户资料入 UserDefaults）
                APIClient.shared.setAuthToken(loginData.token)
                APIClient.saveUser(id: loginData.user.id, phone: loginData.user.phone, nickname: loginData.user.nickname)

                // 登录成功后预取 UDID 签名令牌
                Task { _ = try? await APIClient.shared.getUdidSign() }

                await MainActor.run {
                    appState.currentUser = AppState.User(
                        id: loginData.user.id,
                        phone: loginData.user.phone,
                        nickname: loginData.user.nickname
                    )
                    appState.isLoggedIn = true
                    isLoggingIn = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = "网络连接失败，请检查网络后重试"
                    showError = true
                }
            }
        }
    }
}
