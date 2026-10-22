import WebKit

/// A small LRU pool of hidden web views that preload search results, so
/// flicking between results swaps in an already-loaded page.
@MainActor
final class ResultPrefetcher {
    private var pool: [(key: String, view: WKWebView)] = []
    private let capacity: Int
    private let makeView: () -> WKWebView

    init(capacity: Int = 4, makeView: @escaping () -> WKWebView) {
        self.capacity = capacity
        self.makeView = makeView
    }

    static func key(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    func contains(_ url: URL) -> Bool {
        let key = Self.key(for: url)
        return pool.contains { $0.key == key }
    }

    /// Removes and returns the preloaded view for `url`, if there is one.
    func take(_ url: URL) -> WKWebView? {
        let key = Self.key(for: url)
        guard let index = pool.firstIndex(where: { $0.key == key }) else { return nil }
        return pool.remove(at: index).view
    }

    /// Keeps an already-loaded view around (e.g. the page you just flicked away from).
    func store(_ view: WKWebView, for url: URL) {
        let key = Self.key(for: url)
        pool.removeAll { $0.key == key }
        view.setAllMediaPlaybackSuspended(true)
        pool.append((key, view))
        evict()
    }

    func prefetch(_ urls: [URL]) {
        for url in urls where !contains(url) {
            let view = makeView()
            view.load(URLRequest(url: url))
            view.setAllMediaPlaybackSuspended(true)
            pool.append((Self.key(for: url), view))
        }
        evict()
    }

    func clear() {
        pool.forEach { $0.view.stopLoading() }
        pool.removeAll()
    }

    private func evict() {
        while pool.count > capacity {
            pool.removeFirst().view.stopLoading()
        }
    }
}
