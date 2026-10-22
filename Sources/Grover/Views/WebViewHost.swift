import SwiftUI
import WebKit

/// Hosts a WKWebView that is owned elsewhere, so pages survive mode changes
/// and a prefetched view can be swapped in without reloading.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = cornerRadius > 0

        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
