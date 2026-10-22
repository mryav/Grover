import SwiftUI

/// Liquid Glass buttons floating over the Google pane: close on the left,
/// history and new search on the right.
struct TopButtons: View {
    @Environment(AppController.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: app.close) {
                GlassSymbol(name: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                historyMenu
                Button(action: app.newSearch) {
                    GlassSymbol(name: "plus")
                }
                .buttonStyle(.plain)
                .help("New search")
            }
        }
    }

    private var historyMenu: some View {
        Menu {
            if app.state.history.isEmpty {
                Text("No recent searches")
            } else {
                ForEach(app.state.history, id: \.self) { query in
                    Button(query) { app.search(query) }
                }
                Divider()
                Button("Clear History") { app.state.clearHistory() }
            }
        } label: {
            GlassSymbol(name: "clock.arrow.trianglehead.counterclockwise.rotate.90")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recent searches")
    }
}

/// 36×36 circular glass button face (macOS 27 "XL" button).
private struct GlassSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
