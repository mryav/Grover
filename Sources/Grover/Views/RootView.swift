import SwiftUI

struct RootView: View {
    @Environment(AppController.self) private var app

    var body: some View {
        Group {
            if app.state.mode == .compact {
                SearchBar(style: .standalone)
            } else {
                ResultsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

/// Google results with the search bar underneath (Figma 1:38 / 1:119), plus the
/// side page when a result is open (1:141 / 1:165).
private struct ResultsView: View {
    @Environment(AppController.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                WebViewHost(webView: app.browser.googleView)
                    .padding(.vertical, 4)
                SearchBar(style: .embedded)
            }
            .frame(width: Theme.columnWidth)
            .overlay(alignment: .top) { TopButtons() }

            if app.state.mode == .split {
                WebViewHost(webView: app.browser.sideView, cornerRadius: 11)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            pageBackground
            WindowDragArea()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Theme.strokeWidth)
        }
    }

    /// Matches the Google page so the window blends with Google's light/dark theme.
    private var pageBackground: Color {
        if let color = app.browser.pageBackground { return Color(nsColor: color) }
        return scheme == .dark ? Theme.googleDark : Theme.googleLight
    }
}
