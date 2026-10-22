import AppKit
import Observation
import WebKit

/// Owns the two web views: the Google pane, which must never leave Google,
/// and the single side page that every non-Google link opens in.
@Observable
@MainActor
final class BrowserController: NSObject {
    @ObservationIgnored let googleView: WKWebView
    private(set) var sideView: WKWebView

    /// Background colour of the current Google page, so the window matches
    /// Google's light or dark theme.
    private(set) var pageBackground: NSColor?

    /// Organic result links scraped from the current Google results page.
    private(set) var results: [URL] = []
    private(set) var currentIndex: Int?

    /// Called when a result opens in the side page.
    @ObservationIgnored var onOpenSide: () -> Void = {}

    @ObservationIgnored private var sideURL: URL?
    @ObservationIgnored private var backgroundObservation: NSKeyValueObservation?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var themeReloadedURL: URL?
    @ObservationIgnored private lazy var prefetcher = ResultPrefetcher { [unowned self] in self.makeSideView() }

    static let home = URL(string: "https://www.google.com/")!

    /// Mobile Safari UA so Google serves the compact layout that fits the 400pt column.
    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.addUserScript(
            WKUserScript(source: Self.resultScraper, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        googleView = WKWebView(frame: .zero, configuration: config)
        googleView.customUserAgent = Self.mobileUserAgent
        googleView.allowsBackForwardNavigationGestures = true

        sideView = Self.newSideView()

        super.init()

        config.userContentController.add(WeakScriptHandler(self), name: "groverResults")
        googleView.navigationDelegate = self
        googleView.uiDelegate = self
        configureSide(sideView)

        backgroundObservation = googleView.observe(\.underPageBackgroundColor, options: [.initial, .new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.pageBackground = view.underPageBackgroundColor }
        }

        // Google picks light/dark when the page loads, so reload on a system theme switch.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { _ = self?.googleView.reload() }
        }

        googleView.load(URLRequest(url: Self.home))
    }

    // MARK: Google pane

    func search(_ query: String) {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        resetResults()
        googleView.load(URLRequest(url: components.url!))
    }

    func loadInGoogle(_ request: URLRequest) {
        resetResults()
        googleView.load(request)
    }

    func reset() {
        resetResults()
        closeSide()
        googleView.load(URLRequest(url: Self.home))
    }

    private func resetResults() {
        results = []
        currentIndex = nil
        prefetcher.clear()
    }

    static func isGoogle(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.range(of: #"(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$"#, options: .regularExpression) != nil
    }

    /// Google result links that bounce off Google to another site:
    /// /url?q=<target> (readable) and /goto?url=<opaque> (mobile results).
    static func isOutboundRedirect(_ url: URL) -> Bool {
        isGoogle(url) && (url.path == "/url" || url.path == "/goto")
    }

    /// The real target of a google.com/url?q=<target> link.
    static func unwrapRedirect(_ url: URL) -> URL? {
        guard isGoogle(url), url.path == "/url",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let target = items.first(where: { $0.name == "q" || $0.name == "url" })?.value,
              let targetURL = URL(string: target), targetURL.scheme?.hasPrefix("http") == true
        else { return nil }
        return targetURL
    }

    /// Sends a URL that the Google pane wants to open to the right place.
    /// Outbound redirects that can't be unwrapped open in the side page as-is,
    /// and the side page follows them.
    private func route(_ url: URL) {
        let target = Self.unwrapRedirect(url) ?? url
        if Self.isGoogle(target), !Self.isOutboundRedirect(target) {
            googleView.load(URLRequest(url: target))
        } else if target.scheme == "http" || target.scheme == "https" {
            openSide(target)
        }
    }

    // MARK: Side page

    func openSide(_ url: URL) {
        let key = ResultPrefetcher.key(for: url)
        if let sideURL, ResultPrefetcher.key(for: sideURL) == key {
            // Already showing it.
        } else if let ready = prefetcher.take(url) {
            if let sideURL { prefetcher.store(sideView, for: sideURL) }
            ready.setAllMediaPlaybackSuspended(false)
            sideView = ready
        } else {
            if let sideURL {
                prefetcher.store(sideView, for: sideURL)
                sideView = makeSideView()
            }
            sideView.load(URLRequest(url: url))
        }
        sideURL = url
        currentIndex = results.firstIndex { ResultPrefetcher.key(for: $0) == key }
        prefetchNeighbours()
        onOpenSide()
    }

    func closeSide() {
        if let sideURL {
            prefetcher.store(sideView, for: sideURL)
            sideView = makeSideView()
        }
        sideURL = nil
        currentIndex = nil
    }

    /// Flicks to the next (+1) or previous (-1) result.
    func step(_ delta: Int) {
        guard !results.isEmpty else { return }
        let next: Int
        if let currentIndex {
            next = currentIndex + delta
        } else {
            next = delta > 0 ? 0 : results.count - 1
        }
        guard results.indices.contains(next) else { return }
        openSide(results[next])
    }

    private func prefetchNeighbours() {
        guard !results.isEmpty else { return }
        let start = currentIndex ?? -1
        let wanted = [start + 1, start + 2, start - 1]
            .filter { results.indices.contains($0) && $0 != currentIndex }
            .map { results[$0] }
        prefetcher.prefetch(wanted)
    }

    fileprivate func receiveResults(_ urls: [URL]) {
        guard urls != results else { return }
        results = urls
        if let sideURL {
            let key = ResultPrefetcher.key(for: sideURL)
            currentIndex = results.firstIndex { ResultPrefetcher.key(for: $0) == key }
        }
        prefetchNeighbours()
    }

    private static func newSideView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: NSRect(origin: .zero, size: Theme.sidePageSize), configuration: config)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    private func makeSideView() -> WKWebView {
        let view = Self.newSideView()
        configureSide(view)
        return view
    }

    private func configureSide(_ view: WKWebView) {
        view.uiDelegate = self
    }

    // MARK: Result scraping

    /// Collects organic result links on Google results pages (including ones
    /// added by infinite scroll) and posts them to `groverResults`.
    private static let resultScraper = #"""
    (() => {
      if (window.__groverScraper) return;
      window.__groverScraper = true;
      const isGoogle = h => /(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$/i.test(h);
      const unwrap = a => {
        try {
          let u = new URL(a.href, location.href);
          if (isGoogle(u.hostname) && u.pathname === '/url') {
            const t = u.searchParams.get('q') || u.searchParams.get('url');
            if (t) u = new URL(t);
          }
          return u;
        } catch (e) { return null; }
      };
      let last = null;
      const collect = () => {
        const root = document.querySelector('#rso') || document.querySelector('#search') || document.querySelector('#main');
        const seen = new Set();
        const out = [];
        if (root && location.pathname === '/search') {
          root.querySelectorAll('a[href]').forEach(a => {
            if (!a.querySelector('h3, [role="heading"]')) return;
            const u = unwrap(a);
            if (!u || !/^https?:$/.test(u.protocol)) return;
            if (isGoogle(u.hostname) && u.pathname !== '/goto') return;
            u.hash = '';
            const s = u.toString();
            if (seen.has(s)) return;
            seen.add(s);
            out.push(s);
          });
        }
        const key = out.join('\n');
        if (key === last) return;
        last = key;
        window.webkit.messageHandlers.groverResults.postMessage(out);
      };
      let timer;
      const schedule = () => { clearTimeout(timer); timer = setTimeout(collect, 200); };
      new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
      collect();
    })();
    """#
}

// MARK: - Navigation policy

extension BrowserController: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // Only the Google pane is restricted; the side page can go anywhere.
        guard webView === googleView,
              let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame ?? true
        else { return decisionHandler(.allow) }

        switch url.scheme?.lowercased() {
        case "about", "data", "blob":
            return decisionHandler(.allow)
        case "http", "https":
            if Self.isGoogle(url), !Self.isOutboundRedirect(url) {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            route(url)
        default:
            // Custom schemes (app links etc.) are never followed from the Google pane.
            decisionHandler(.cancel)
        }
    }

    /// Backstop: if a navigation somehow commits off Google, move it to the side.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === googleView, let url = webView.url,
              url.scheme?.hasPrefix("http") == true, !Self.isGoogle(url)
        else { return }
        webView.stopLoading()
        if webView.canGoBack { webView.goBack() } else { webView.load(URLRequest(url: Self.home)) }
        openSide(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === googleView else { return }
        pageBackground = webView.underPageBackgroundColor
        reloadIfThemeMismatched()
    }

    /// Google remembers the last theme it served, so the first page after a
    /// light/dark switch can come back in the old theme. Reload it once.
    private func reloadIfThemeMismatched() {
        guard let color = googleView.underPageBackgroundColor.usingColorSpace(.sRGB),
              let url = googleView.url, url != themeReloadedURL
        else { return }
        let pageIsDark = color.brightnessComponent < 0.5
        let wantsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard pageIsDark != wantsDark else { return }
        themeReloadedURL = url
        googleView.reload()
    }

    /// target=_blank / window.open: never open a new window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if webView === googleView {
            route(url)
        } else {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - Script messages

/// Breaks the WKUserContentController -> handler retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var browser: BrowserController?

    init(_ browser: BrowserController) { self.browser = browser }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let strings = message.body as? [String] else { return }
        let urls = strings.compactMap(URL.init(string:))
        MainActor.assumeIsolated { browser?.receiveResults(urls) }
    }
}
