import SwiftUI
import WebKit

struct StageContentWebView: NSViewRepresentable {
    enum Content {
        case html(String)
        case svg(String)
    }
    var content: Content

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.suppressesIncrementalRendering = false
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        switch content {
        case .html(let html):
            webView.loadHTMLString(html, baseURL: nil)
        case .svg(let svg):
            if let data = svg.data(using: .utf8) {
                webView.load(data, mimeType: "image/svg+xml", characterEncodingName: "utf-8", baseURL: URL(fileURLWithPath: "/"))
            }
        }
    }
}
