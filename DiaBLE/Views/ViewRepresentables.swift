import Foundation
import SwiftUI
import WebKit


struct WebView: UIViewRepresentable {

    var site: String
    var endpoint: String = ""
    var query: String = ""
    var delegate: (WKNavigationDelegate & WKUIDelegate)!

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        (delegate as? Nightscout)?.webView = webView
        return webView
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        var url = "https://" + site
        if !endpoint.isEmpty {
            url += ("/" + endpoint)
        }
        if !query.isEmpty {
            url += ("?" + query)
        }
        if let url = URL(string: url) {
            view.load(URLRequest(url: url))
        }
    }
}
