import SwiftUI
import WebKit

/// Hosts a tab's long-lived WKWebView so switching tabs keeps each page's state.
struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        // Autoresizing rather than Auto Layout constraints: constraints inside SwiftUI's hosting
        // view can trigger an endless "update constraints" loop that AppKit kills the app for.
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        container.addSubview(webView)
    }
}

enum Sites {
    struct Site: Identifiable {
        let name: String
        let url: URL
        let symbol: String
        var id: String { name }
    }

    static let all: [Site] = [
        Site(name: "FamilySearch", url: URL(string: "https://www.familysearch.org")!, symbol: "tree"),
        Site(name: "WikiTree", url: URL(string: "https://www.wikitree.com")!, symbol: "person.3"),
        Site(name: "Find a Grave", url: URL(string: "https://www.findagrave.com")!, symbol: "leaf"),
        Site(name: "Généalogie Québec (Drouin)", url: URL(string: "https://www.genealogiequebec.com")!, symbol: "book.closed"),
    ]

    /// Treats input with a dot and no spaces as an address; anything else becomes a web search.
    static func url(fromAddressBar input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://"), let url = URL(string: text) { return url }
        if text.contains("."), !text.contains(" "), let url = URL(string: "https://\(text)") { return url }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }
}
