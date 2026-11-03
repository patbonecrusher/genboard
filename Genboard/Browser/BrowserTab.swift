import AppKit
import Observation
import WebKit

@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    @ObservationIgnored let webView: WKWebView
    private(set) var title = "New Tab"
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    /// The history entry for the page currently shown in this tab.
    @ObservationIgnored var currentVisit: Visit?
    @ObservationIgnored var onURLChange: ((BrowserTab) -> Void)?
    @ObservationIgnored var onTitleChange: ((BrowserTab) -> Void)?
    @ObservationIgnored var onOpenInNewTab: ((URL) -> Void)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let uiDelegate = TabUIDelegate()

    /// Some genealogy sites refuse browsers they don't recognize, so present as Safari.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Safari/605.1.15"

    init(url: URL?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()  // persistent, so site logins survive restarts
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        uiDelegate.tab = self
        webView.uiDelegate = uiDelegate

        observations = [
            webView.observe(\.url) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncURL() }
            },
            webView.observe(\.title) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncTitle() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncNavigationState() }
            },
        ]
        if let url { load(url) }
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func snapshotPNG() async -> Data? {
        await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                continuation.resume(returning: image.flatMap(ImageUtil.pngData))
            }
        }
    }

    func evaluateString(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    private func syncURL() {
        url = webView.url
        syncNavigationState()
        onURLChange?(self)
    }

    private func syncTitle() {
        if let title = webView.title, !title.isEmpty {
            self.title = title
        }
        onTitleChange?(self)
    }

    private func syncNavigationState() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

/// Opens target="_blank" links and window.open() calls as new tabs.
final class TabUIDelegate: NSObject, WKUIDelegate {
    weak var tab: BrowserTab?

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            tab?.onOpenInNewTab?(url)
        }
        return nil
    }
}
