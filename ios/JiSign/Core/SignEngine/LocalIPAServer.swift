import Foundation
import Network
import Security

/// 本地 HTTPS 安装服务器 — 使用 local.susuq.top 域名 + Let's Encrypt 证书
/// 与全能签相同方案：零上传，秒安装
class LocalIPAServer {
    static let shared = LocalIPAServer()

    private var listener: NWListener?
    private var ipaPath: String = ""
    private var manifestData: Data?
    private(set) var port: UInt16 = 0
    private var isRunning = false

    static let domain = "local.susuq.top"

    /// 启动 HTTPS 服务器，提供签名后的 IPA + manifest.plist
    func start(ipaPath: String, bundleID: String, appName: String, completion: @escaping (Result<UInt16, Error>) -> Void) {
        stop()
        self.ipaPath = ipaPath

        // 加载 TLS 证书
        guard let tlsOptions = createTLSOptions() else {
            completion(.failure(NSError(domain: "JiSign", code: -1, userInfo: [NSLocalizedDescriptionKey: "TLS 证书加载失败"])))
            return
        }

        let params = NWParameters(tls: tlsOptions, tcp: .init())

        do {
            listener = try NWListener(using: params)
        } catch {
            completion(.failure(error))
            return
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let p = self?.listener?.port?.rawValue ?? 0
                self?.port = p
                self?.isRunning = true

                // 生成 manifest.plist
                let ipaURL = "https://\(Self.domain):\(p)/signed.ipa"
                self?.manifestData = Self.generateManifest(ipaURL: ipaURL, bundleID: bundleID, appName: appName)

                print("[LocalIPAServer] HTTPS 启动成功，端口: \(p)")
                completion(.success(p))

            case .failed(let error):
                print("[LocalIPAServer] 启动失败: \(error)")
                completion(.failure(error))

            default:
                break
            }
        }

        listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    /// 获取 itms-services 安装 URL
    func getInstallURL() -> String {
        let manifestURL = "https://\(Self.domain):\(port)/manifest.plist"
        return "itms-services://?action=download-manifest&url=\(manifestURL)"
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0
        manifestData = nil
    }

    // MARK: - TLS 配置

    /// 从服务器下载最新 SSL 证书（证书续期后无需更新 App）
    static func downloadLatestCert() async -> Bool {
        let certURL = URL(string: "https://api.susuq.top/api/cert/local-ssl")!
        let localPath = FileManager.default.temporaryDirectory.appendingPathComponent("local_ssl.p12")
        do {
            let (data, _) = try await URLSession.shared.data(from: certURL)
            try data.write(to: localPath)
            print("[LocalIPAServer] 证书已更新: \(data.count) bytes")
            return true
        } catch {
            print("[LocalIPAServer] 下载证书失败: \(error)")
            return false
        }
    }

    private func createTLSOptions() -> NWProtocolTLS.Options? {
        // 优先使用动态下载的证书，其次使用 App 内置的
        let dynamicP12 = FileManager.default.temporaryDirectory.appendingPathComponent("local_ssl.p12")
        let bundledP12 = Bundle.main.url(forResource: "server", withExtension: "p12")

        guard let p12URL = FileManager.default.fileExists(atPath: dynamicP12.path) ? dynamicP12 : bundledP12,
              let p12Data = try? Data(contentsOf: p12URL) else {
            print("[LocalIPAServer] 找不到证书文件")
            return nil
        }

        let password = "1"  // 内测侠默认 P12 密码
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity as String] else {
            print("[LocalIPAServer] PKCS12 导入失败: \(status)")
            return nil
        }

        let secIdentity = identity as! SecIdentity
        let tlsOptions = NWProtocolTLS.Options()

        guard let secIdentityRef = sec_identity_create(secIdentity) else {
            print("[LocalIPAServer] sec_identity_create 失败")
            return nil
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentityRef)
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

        return tlsOptions
    }

    // MARK: - 连接处理

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))

        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, error == nil, let data = data else {
                conn.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""

            if request.contains("manifest.plist") {
                self.sendManifest(conn)
            } else if request.contains("signed.ipa") {
                if request.hasPrefix("HEAD") {
                    self.sendIPAHead(conn)
                } else {
                    self.sendIPAFile(conn)
                }
            } else {
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(response.utf8), completion: .contentProcessed({ _ in conn.cancel() }))
            }
        }
    }

    /// 发送 manifest.plist
    private func sendManifest(_ conn: NWConnection) {
        guard let manifest = manifestData else {
            conn.cancel()
            return
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: \(manifest.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(manifest)
        conn.send(content: response, completion: .contentProcessed({ _ in conn.cancel() }))
    }

    /// 发送 IPA 的 HEAD 响应（iOS 先 HEAD 确认大小）
    private func sendIPAHead(_ conn: NWConnection) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: ipaPath)
        let fileSize = (attrs?[.size] as? Int64) ?? 0
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(fileSize)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8), completion: .contentProcessed({ _ in conn.cancel() }))
    }

    /// 流式发送 IPA 文件
    private func sendIPAFile(_ conn: NWConnection) {
        guard FileManager.default.fileExists(atPath: ipaPath),
              let handle = FileHandle(forReadingAtPath: ipaPath) else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(response.utf8), completion: .contentProcessed({ _ in conn.cancel() }))
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: ipaPath)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"signed.ipa\"\r\nContent-Length: \(fileSize)\r\nConnection: close\r\n\r\n"

        conn.send(content: Data(header.utf8), completion: .contentProcessed({ [weak self] error in
            guard error == nil else { conn.cancel(); return }
            self?.sendChunks(conn, handle: handle)
        }))
    }

    /// 分块发送（64KB/块）
    private func sendChunks(_ conn: NWConnection, handle: FileHandle) {
        let chunk = handle.readData(ofLength: 65536)
        if chunk.isEmpty {
            try? handle.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
                conn.cancel()
            }))
            return
        }
        conn.send(content: chunk, completion: .contentProcessed({ [weak self] error in
            if error != nil { try? handle.close(); conn.cancel(); return }
            self?.sendChunks(conn, handle: handle)
        }))
    }

    // MARK: - Manifest 生成

    static func generateManifest(ipaURL: String, bundleID: String, appName: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>items</key>
          <array>
            <dict>
              <key>assets</key>
              <array>
                <dict>
                  <key>kind</key><string>software-package</string>
                  <key>url</key><string>\(ipaURL)</string>
                </dict>
              </array>
              <key>metadata</key>
              <dict>
                <key>bundle-identifier</key><string>\(bundleID)</string>
                <key>bundle-version</key><string>1.0.0</string>
                <key>kind</key><string>software</string>
                <key>title</key><string>\(appName)</string>
              </dict>
            </dict>
          </array>
        </dict>
        </plist>
        """
        return Data(plist.utf8)
    }
}
