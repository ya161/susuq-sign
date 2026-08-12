import Foundation

/// 401 未授权通知 — App 可监听此通知清理登录态并跳转登录页
extension Notification.Name {
    static let jiSignUnauthorized = Notification.Name("JiSignUnauthorized")
}

/// 速签 API 客户端
class APIClient {
    static let shared = APIClient()

    private let baseURL: String
    /// 直连服务器 URL（绕过 Cloudflare 的 100MB 上传限制）
    private let directURL = "http://39.96.76.211"
    private let session: URLSession
    private var authToken: String?
    private var udidSig: String?  // UDID 签名令牌，登录后从 /api/udid/sign 获取

    private static let tokenKey = "jisign_auth_token"
    private static let userKey = "jisign_user_info"

    private init() {
        self.baseURL = "https://api.susuq.top"
        self.session = URLSession.shared
        // 启动时从 Keychain 恢复 token；如已过期则清掉
        if let token = KeychainHelper.load(forKey: Self.tokenKey) {
            if JWTInspector.isExpired(token) {
                print("[APIClient] token 已过期，清理本地登录态")
                KeychainHelper.delete(forKey: Self.tokenKey)
                UserDefaults.standard.removeObject(forKey: Self.userKey)
            } else {
                self.authToken = token
            }
        }
    }

    func setAuthToken(_ token: String) {
        self.authToken = token
        KeychainHelper.save(token, forKey: Self.tokenKey)
    }

    func clearAuth() {
        self.authToken = nil
        self.udidSig = nil
        KeychainHelper.delete(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    var isAuthenticated: Bool {
        guard let token = authToken else { return false }
        return !JWTInspector.isExpired(token)
    }

    /// 保存用户信息（非敏感资料用 UserDefaults 即可）
    static func saveUser(id: Int64, phone: String, nickname: String) {
        let info: [String: Any] = ["id": id, "phone": phone, "nickname": nickname]
        UserDefaults.standard.set(info, forKey: userKey)
    }

    /// 恢复用户信息
    static func loadUser() -> (id: Int64, phone: String, nickname: String)? {
        guard let info = UserDefaults.standard.dictionary(forKey: userKey),
              let id = info["id"] as? Int64,
              let phone = info["phone"] as? String,
              let nickname = info["nickname"] as? String else { return nil }
        return (id, phone, nickname)
    }

    // MARK: - UDID 签名

    /// 获取 UDID 签名令牌（登录后调用一次，缓存在内存里）
    func getUdidSign() async throws -> UdidSignResponse {
        let resp: UdidSignResponse = try await get("/api/udid/sign")
        if resp.success, let sig = resp.data?.sig {
            self.udidSig = sig
        }
        return resp
    }

    /// 已缓存的 UDID 签名
    var cachedUdidSig: String? { udidSig }

    // MARK: - 证书相关

    /// 下载证书文件（P12 + mobileprovision）
    func downloadCert(batchNo: String) async throws -> CertGenerateResponse {
        let body: [String: Any] = ["batch_no": batchNo]
        return try await post("/api/cert/download", body: body)
    }

    /// 购买证书
    func purchaseCert(udid: String, productType: String = "personal_cert", paymentMethod: String = "alipay") async throws -> PurchaseResponse {
        let body: [String: Any] = [
            "udid": udid,
            "product_type": productType,
            "payment_method": paymentMethod
        ]
        return try await post("/api/cert/purchase", body: body)
    }

    /// 生成证书（支付成功后调用）
    func generateCert(orderNo: String, udid: String) async throws -> CertGenerateResponse {
        let body: [String: Any] = [
            "order_no": orderNo,
            "udid": udid
        ]
        return try await post("/api/cert/generate", body: body)
    }

    /// 获取证书列表
    func getCertList() async throws -> CertListResponse {
        return try await get("/api/cert/list")
    }

    /// 检查证书有效性
    func checkCertValid(batchNo: String) async throws -> CertCheckResponse {
        return try await post("/api/cert/check/0?batch_no=\(batchNo)", body: [:])
    }

    // MARK: - UDID 相关

    /// 检查 UDID 是否已获取
    func checkUDID(userID: String) async throws -> UDIDCheckResponse {
        // 登录用户必须带 sig（服务端签名校验）
        if userID != "0", udidSig == nil {
            _ = try? await getUdidSign()
        }
        var path = "/api/udid/check?user_id=\(userID)"
        if let sig = udidSig {
            path += "&sig=\(sig)"
        }
        return try await get(path)
    }

    /// 构建 UDID 获取的 config URL（Safari 打开）
    func udidConfigURL(userID: String) -> String {
        var url = "\(baseURL)/api/udid/config?user_id=\(userID)"
        if let sig = udidSig, userID != "0" {
            url += "&sig=\(sig)"
        }
        return url
    }

    // MARK: - 支付相关

    /// 创建支付宝支付（返回支付链接）
    func createAlipayPayment(orderNo: String) async throws -> AlipayPayResponse {
        let body: [String: Any] = ["order_no": orderNo]
        return try await post("/api/pay/alipay/create", body: body)
    }

    // MARK: - 认证相关

    /// 发送验证码
    func sendSMSCode(phone: String) async throws -> SMSCodeResponse {
        let body: [String: Any] = ["phone": phone]
        return try await post("/api/auth/sms-code", body: body)
    }

    /// 手机号+验证码登录
    func login(phone: String, code: String) async throws -> LoginResponse {
        let body: [String: Any] = ["phone": phone, "code": code]
        return try await post("/api/auth/login", body: body)
    }

    // MARK: - App 更新

    /// 检查最新版本
    func checkVersion() async throws -> VersionResponse {
        return try await get("/api/app/version")
    }

    /// 获取更新安装链接
    func getUpdateURL() async throws -> UpdateResponse {
        return try await post("/api/app/update", body: [:])
    }

    // MARK: - 订单相关

    /// 获取订单列表
    func getOrders() async throws -> OrderListResponse {
        return try await get("/api/orders")
    }

    // MARK: - 设备相关

    /// 获取设备列表
    func getDevices() async throws -> DeviceListResponse {
        return try await get("/api/devices")
    }

    // MARK: - 签名 IPA 安装

    /// 上传原始 IPA 到服务端签名安装（服务端 zsign 产出格式正确的 IPA）
    func remoteSignAndInstall(ipaURL: URL, bundleID: String, appName: String, progress: @escaping (Double) -> Void) async throws -> InstallUploadResponse {
        let boundary = UUID().uuidString

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("upload_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmpFile)

        func writeStr(_ s: String) { handle.write(Data(s.utf8)) }

        if !bundleID.isEmpty {
            writeStr("--\(boundary)\r\nContent-Disposition: form-data; name=\"bundle_id\"\r\n\r\n\(bundleID)\r\n")
        }
        if !appName.isEmpty {
            writeStr("--\(boundary)\r\nContent-Disposition: form-data; name=\"app_name\"\r\n\r\n\(appName)\r\n")
        }
        writeStr("--\(boundary)\r\nContent-Disposition: form-data; name=\"ipa\"; filename=\"app.ipa\"\r\nContent-Type: application/octet-stream\r\n\r\n")

        guard let input = InputStream(url: ipaURL) else {
            throw NSError(domain: "JiSign", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法读取 IPA"])
        }
        input.open()
        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate(); input.close() }
        while input.hasBytesAvailable {
            let read = input.read(buf, maxLength: bufSize)
            if read > 0 { handle.write(Data(bytes: buf, count: read)) }
            else { break }
        }
        writeStr("\r\n--\(boundary)--\r\n")
        try handle.close()

        // 直连服务器 IP（绕过 Cloudflare 100MB 限制）
        var request = URLRequest(url: URL(string: directURL + "/api/install/sign")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await UploadHelper.uploadAndDecode(request: request, fileURL: tmpFile, progress: progress)
    }

    /// 上传已签名 IPA 到服务器（备用方案）
    func uploadSignedIPA(ipaURL: URL, bundleID: String, appName: String, progress: @escaping (Double) -> Void) async throws -> InstallUploadResponse {
        let boundary = UUID().uuidString

        // 用临时文件构建 multipart body，避免大 IPA 占爆内存
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("upload_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmpFile)
        defer { try? handle.close() }

        func writeStr(_ s: String) { handle.write(Data(s.utf8)) }

        writeStr("--\(boundary)\r\nContent-Disposition: form-data; name=\"bundle_id\"\r\n\r\n\(bundleID)\r\n")
        writeStr("--\(boundary)\r\nContent-Disposition: form-data; name=\"app_name\"\r\n\r\n\(appName)\r\n")
        writeStr("--\(boundary)\r\nContent-Disposition: form-data; name=\"ipa\"; filename=\"signed.ipa\"\r\nContent-Type: application/octet-stream\r\n\r\n")

        // 流式写入 IPA
        guard let input = InputStream(url: ipaURL) else {
            throw NSError(domain: "JiSign", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法读取签名 IPA"])
        }
        input.open()
        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate(); input.close() }
        while input.hasBytesAvailable {
            let read = input.read(buf, maxLength: bufSize)
            if read > 0 { handle.write(Data(bytes: buf, count: read)) }
            else { break }
        }

        writeStr("\r\n--\(boundary)--\r\n")
        try handle.close()

        // 直连服务器 IP 上传（绕过 Cloudflare 100MB 上传限制）
        var request = URLRequest(url: URL(string: directURL + "/api/install/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 使用带进度回调的上传
        let data = try await UploadHelper.upload(request: request, fileURL: tmpFile, progress: progress)
        return try JSONDecoder().decode(InstallUploadResponse.self, from: data)
    }

    // MARK: - 通用请求

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "GET"
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// 发送请求并统一处理 401（清本地登录态 + 广播通知）
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            clearAuth()
            NotificationCenter.default.post(name: .jiSignUnauthorized, object: nil)
            throw NSError(
                domain: "JiSign",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "登录已过期，请重新登录"]
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - 上传助手（支持进度回调）

class UploadHelper: NSObject, URLSessionTaskDelegate {
    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<Data, Error>?

    static func upload(request: URLRequest, fileURL: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        let helper = UploadHelper()
        helper.progressHandler = progress
        return try await withCheckedThrowingContinuation { cont in
            helper.continuation = cont
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600
            let session = URLSession(configuration: config, delegate: helper, delegateQueue: nil)
            let task = session.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let data = data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: NSError(domain: "JiSign", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传无响应"]))
                }
            }
            task.resume()
        }
    }

    static func uploadAndDecode<T: Decodable>(request: URLRequest, fileURL: URL, progress: @escaping (Double) -> Void) async throws -> T {
        let data = try await upload(request: request, fileURL: fileURL, progress: progress)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let pct = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(pct)
        }
    }
}

// MARK: - 响应模型

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}

struct PurchaseResponse: Decodable {
    let success: Bool
    let data: PurchaseData?
    let error: String?

    struct PurchaseData: Decodable {
        let orderNo: String
        let amount: Double
        let paymentURL: String?
        let productType: String?

        enum CodingKeys: String, CodingKey {
            case orderNo = "order_no"
            case amount
            case paymentURL = "payment_url"
            case productType = "product_type"
        }
    }
}

struct CertGenerateResponse: Decodable {
    let success: Bool
    let data: CertData?
    let error: String?

    struct CertData: Decodable {
        let p12Data: String
        let mobileprovisionData: String
        let udidBatchNo: String

        enum CodingKeys: String, CodingKey {
            case p12Data = "p12_data"
            case mobileprovisionData = "mobileprovision_data"
            case udidBatchNo = "udid_batch_no"
        }
    }
}

struct CertListResponse: Decodable {
    let success: Bool
    let data: [CertInfo]?
    let error: String?

    struct CertInfo: Decodable {
        let id: Int64
        let batchNo: String
        let status: String
        let expireAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case batchNo = "udid_batch_no"
            case status
            case expireAt = "expire_at"
        }
    }
}

struct CertCheckResponse: Decodable {
    let success: Bool
    let data: CertCheckData?
    let error: String?

    struct CertCheckData: Decodable {
        let valid: Bool
    }
}

struct AlipayPayResponse: Decodable {
    let success: Bool
    let data: AlipayPayData?
    let error: String?

    struct AlipayPayData: Decodable {
        let paymentURL: String
        let orderNo: String
        let amount: Double

        enum CodingKeys: String, CodingKey {
            case paymentURL = "payment_url"
            case orderNo = "order_no"
            case amount
        }
    }
}

struct SMSCodeResponse: Decodable {
    let success: Bool
    let data: SMSData?
    let error: String?

    struct SMSData: Decodable {
        let message: String
        let debugCode: String?

        enum CodingKeys: String, CodingKey {
            case message
            case debugCode = "debugCode"
        }
    }
}

struct LoginResponse: Decodable {
    let success: Bool
    let data: LoginData?
    let error: String?

    struct LoginData: Decodable {
        let token: String
        let user: UserData

        struct UserData: Decodable {
            let id: Int64
            let phone: String
            let nickname: String

            enum CodingKeys: String, CodingKey {
                case id
                case phone
                case nickname
            }
        }
    }
}

struct OrderListResponse: Decodable {
    let success: Bool
    let data: [OrderData]?
    let error: String?

    struct OrderData: Decodable {
        let id: Int64
        let orderNo: String
        let productType: String
        let amount: Double
        let paymentStatus: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case orderNo = "order_no"
            case productType = "product_type"
            case amount
            case paymentStatus = "payment_status"
            case createdAt = "created_at"
        }
    }
}

struct UDIDCheckResponse: Decodable {
    let success: Bool
    let data: UDIDCheckData?
    let error: String?

    struct UDIDCheckData: Decodable {
        let found: Bool
        let udid: String?
    }
}

struct UdidSignResponse: Decodable {
    let success: Bool
    let data: UdidSignData?
    let error: String?

    struct UdidSignData: Decodable {
        let sig: String
        let configURL: String?

        enum CodingKeys: String, CodingKey {
            case sig
            case configURL = "config_url"
        }
    }
}

struct DeviceListResponse: Decodable {
    let success: Bool
    let data: [DeviceData]?
    let error: String?

    struct DeviceData: Decodable {
        let id: Int64
        let udid: String
        let model: String
        let iosVersion: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case udid
            case model
            case iosVersion = "ios_version"
            case createdAt = "created_at"
        }
    }
}

struct VersionResponse: Decodable {
    let success: Bool
    let data: VersionData?
    let error: String?

    struct VersionData: Decodable {
        let version: String
        let build: String
        let updateNote: String
        let force: Bool

        enum CodingKeys: String, CodingKey {
            case version
            case build
            case updateNote = "update_note"
            case force
        }
    }
}

struct InstallUploadResponse: Decodable {
    let success: Bool
    let data: InstallUploadData?
    let error: String?

    struct InstallUploadData: Decodable {
        let token: String
        let installURL: String

        enum CodingKeys: String, CodingKey {
            case token
            case installURL = "install_url"
        }
    }
}

struct UpdateResponse: Decodable {
    let success: Bool
    let data: UpdateData?
    let error: String?

    struct UpdateData: Decodable {
        let installURL: String
        let batchNo: String
        let version: String

        enum CodingKeys: String, CodingKey {
            case installURL = "install_url"
            case batchNo = "batch_no"
            case version
        }
    }
}

