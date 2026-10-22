import AppKit
import Observation

/// Ties the state, web views and panel together; the views call into this.
@Observable
@MainActor
final class AppController {
    let state = AppState()
    let browser = BrowserController()

    @ObservationIgnored private(set) lazy var panel = PanelController(app: self)
    @ObservationIgnored private let dictation = Dictation()
    /// True while the Lens file picker is up, so losing focus to it doesn't hide the bar.
    @ObservationIgnored private var isChoosingImage = false

    init() {
        browser.onOpenSide = { [weak self] in self?.setMode(.split) }
    }

    // MARK: Window

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        panel.show(mode: state.mode)
        state.focusRequest += 1
    }

    func hide() {
        stopDictation()
        panel.hide()
    }

    /// Clicking outside the small search bar dismisses it. Once a search is
    /// showing, the window stays put until closed.
    func panelDidResignKey() {
        guard state.mode == .compact, panel.isVisible, !isChoosingImage, !state.isListening else { return }
        hide()
    }

    func setMode(_ mode: Mode) {
        guard mode != state.mode else { return }
        if state.mode == .split { browser.closeSide() }
        state.mode = mode
        panel.apply(mode, animated: true)
    }

    // MARK: Actions

    func submit() {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        search(query)
    }

    func search(_ query: String) {
        stopDictation()
        state.remember(query)
        state.query = ""
        browser.search(query)
        setMode(.expanded)
        state.focusRequest += 1
    }

    /// Top "+" button: start over from the small search bar.
    func newSearch() {
        stopDictation()
        state.query = ""
        setMode(.compact)
        browser.reset()
        state.focusRequest += 1
    }

    /// Top "✕" button: reset and hide.
    func close() {
        newSearch()
        hide()
    }

    func toggleDictation() {
        if state.isListening {
            stopDictation()
            return
        }
        let base = state.query.trimmingCharacters(in: .whitespaces)
        state.isListening = true
        dictation.start(
            onText: { [weak self] text in
                self?.state.query = base.isEmpty ? text : base + " " + text
            },
            onEnd: { [weak self] in
                self?.state.isListening = false
            }
        )
    }

    private func stopDictation() {
        dictation.stop()
        state.isListening = false
    }

    func searchWithLens() {
        stopDictation()
        NSApp.activate()
        isChoosingImage = true
        let chosen = LensUpload.chooseImage()
        isChoosingImage = false
        guard let file = chosen else {
            panel.panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let request = LensUpload.request(for: file) else {
            NSSound.beep()
            return
        }
        browser.loadInGoogle(request)
        setMode(.expanded)
        panel.panel.makeKeyAndOrderFront(nil)
    }

    // MARK: Keyboard

    /// Panel-wide shortcuts. Returns true when the event was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        // Arrow keys also carry .numericPad/.function, so only compare real modifiers.
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, flags) {
        case (53, []): // Esc
            if state.mode == .split {
                setMode(.expanded)
            } else {
                hide()
            }
            return true
        case (125, [.command]): // ⌘↓
            browser.step(1)
            return true
        case (126, [.command]): // ⌘↑
            browser.step(-1)
            return true
        case (45, [.command]): // ⌘N
            newSearch()
            return true
        case (13, [.command]): // ⌘W
            if state.mode == .split { setMode(.expanded) } else { hide() }
            return true
        default:
            return false
        }
    }
}
