import SwiftUI

/// "Search Google" bar. `.standalone` is the small window on its own (Figma
/// 1:10 / 1:93); `.embedded` sits under the Google results (1:38 / 1:119).
struct SearchBar: View {
    enum Style { case standalone, embedded }

    let style: Style

    @Environment(AppController.self) private var app
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var isDark: Bool { scheme == .dark }
    private var radius: CGFloat { style == .standalone ? 16 : 10 }

    var body: some View {
        @Bindable var state = app.state

        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                if state.query.isEmpty {
                    Text("Search Google")
                        .foregroundStyle(placeholderColor)
                        .allowsHitTesting(false)
                }
                TextField("", text: $state.query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(isDark ? Color.white : Color.black)
                    .focused($focused)
                    .onSubmit(app.submit)
            }
            .font(Theme.searchFont())
            .tracking(Theme.searchTracking)
            .frame(height: 19)
            .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 0) {
                Image(nsImage: Theme.image("google-g.png"))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                Spacer(minLength: 0)
                HStack(spacing: 16) {
                    IconButton(image: isDark ? "mic-dark.svg" : "mic.svg", help: "Dictate", action: app.toggleDictation)
                        .background {
                            if state.isListening {
                                Circle().fill(Color.red.opacity(0.25)).frame(width: 32, height: 32)
                            }
                        }
                    IconButton(image: isDark ? "add-dark.svg" : "add.svg", help: "Search an image with Google Lens", action: app.searchWithLens)
                    IconButton(image: sendImage, help: "Search Google", action: app.submit)
                }
            }
        }
        // Figma strokes sit inside the frame, so content starts 1pt further in.
        .padding(.top, 17)
        .padding(.horizontal, 17)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            background
            WindowDragArea()
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: Theme.strokeWidth)
        }
        .onAppear { focused = true }
        .onChange(of: state.focusRequest) { focused = true }
    }

    private var placeholderColor: Color {
        style == .standalone && isDark ? .white : Theme.placeholder
    }

    private var borderColor: Color {
        switch (style, isDark) {
        case (.standalone, false), (.embedded, false): Theme.border
        case (.standalone, true): .black
        case (.embedded, true): Theme.borderDarkEmbedded
        }
    }

    private var sendImage: String {
        if !app.state.query.trimmingCharacters(in: .whitespaces).isEmpty { return "send-active.svg" }
        return isDark ? "send-idle-dark.svg" : "send-idle.svg"
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch (style, isDark) {
        case (.standalone, _):
            // The window's own shadow stands in for the Figma drop shadow.
            shape.fill(isDark ? Color.black : Color.white)
        case (.embedded, false):
            shape.fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 7.35, y: 4)
                .shadow(color: .white.opacity(0.7), radius: 1.3, y: 11)
        case (.embedded, true):
            shape.fill(Color.black)
                .shadow(color: .black.opacity(0.1), radius: 3.7, y: 4)
                .shadow(color: .black.opacity(0.7), radius: 0.65, y: 11)
        }
    }
}

/// 24×24 icon from the Figma assets.
private struct IconButton: View {
    let image: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(nsImage: Theme.image(image))
                .resizable()
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
