import SwiftUI
import WebKit

// MARK: - 内置浏览器视图

struct BrowserView: View {
    @State private var urlString = "https://www.google.com"
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var pageTitle = ""
    @State private var downloadProgress: Double?
    @State private var downloadFileName = ""
    @State private var showDownloadAlert = false
    @State private var pendingDownloadURL: URL?

    @StateObject private var webViewStore = WebViewStore()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 地址栏
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(urlString.hasPrefix("https") ? .green : .secondary)

                TextField("输入网址", text: $urlString)
                    .textFieldStyle(.plain)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onSubmit {
                        loadURL()
                    }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        loadURL()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.jsPrimary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // MARK: - 下载进度
            if let progress = downloadProgress {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.jsPrimary)
                        Text("正在下载: \(downloadFileName)")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.jsPrimary)
                    }
                    ProgressView(value: progress)
                        .tint(.jsPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.jsPrimary.opacity(0.05))
            }

            // MARK: - WebView
            BrowserWebView(
                store: webViewStore,
                urlString: $urlString,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                pageTitle: $pageTitle,
                onIPADetected: { url in
                    pendingDownloadURL = url
                    downloadFileName = url.lastPathComponent
                    showDownloadAlert = true
                }
            )

            // MARK: - 底部导航栏
            HStack(spacing: 0) {
                ToolbarButton(icon: "chevron.left", enabled: canGoBack) {
                    webViewStore.webView.goBack()
                }
                ToolbarButton(icon: "chevron.right", enabled: canGoForward) {
                    webViewStore.webView.goForward()
                }
                ToolbarButton(icon: "arrow.clockwise", enabled: true) {
                    webViewStore.webView.reload()
                }
                ToolbarButton(icon: "square.and.arrow.up", enabled: true) {
                    // TODO: 分享当前网址
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
        }
        .navigationTitle(pageTitle.isEmpty ? "浏览器" : pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert("检测到 IPA 文件", isPresented: $showDownloadAlert) {
            Button("下载") {
                if let url = pendingDownloadURL {
                    startDownload(url: url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("是否下载「\(downloadFileName)」到本地？")
        }
        .onAppear {
            loadURL()
        }
    }

    // MARK: - 加载 URL

    private func loadURL() {
        var finalURL = urlString
        if !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
            finalURL = "https://" + finalURL
        }
        guard let url = URL(string: finalURL) else { return }
        webViewStore.webView.load(URLRequest(url: url))
    }

    // MARK: - 下载 IPA

    private func startDownload(url: URL) {
        downloadProgress = 0
        downloadFileName = url.lastPathComponent
        // TODO: 使用 URLSession 下载到 App 沙盒
        // 模拟下载
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if let progress = downloadProgress {
                downloadProgress = progress + 0.03
                if progress >= 1.0 {
                    downloadProgress = nil
                    timer.invalidate()
                }
            }
        }
    }
}

// MARK: - 底部工具按钮

private struct ToolbarButton: View {
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .foregroundColor(enabled ? .jsPrimary : .secondary.opacity(0.4))
        }
        .disabled(!enabled)
    }
}

// MARK: - WebView 存储

class WebViewStore: ObservableObject {
    let webView = WKWebView()
}

// MARK: - WKWebView 封装

struct BrowserWebView: UIViewRepresentable {
    let store: WebViewStore
    @Binding var urlString: String
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var pageTitle: String
    var onIPADetected: (URL) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = store.webView
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BrowserWebView

        init(_ parent: BrowserWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.pageTitle = webView.title ?? ""
            parent.urlString = webView.url?.absoluteString ?? ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        // 拦截 .ipa 文件下载链接
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               url.pathExtension.lowercased() == "ipa" {
                parent.onIPADetected(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
