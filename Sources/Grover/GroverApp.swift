import AppKit

@main
@MainActor
enum GroverMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: AppController!
    private let hotkey = HotkeyMonitor()
    private var statusItem: NSStatusItem!
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        NSApp.mainMenu = Self.makeMainMenu()

        controller = AppController()
        _ = controller.panel

        hotkey.onTrigger = { [weak self] in self?.controller.toggle() }
        if !HotkeyMonitor.isTrusted { HotkeyMonitor.promptForAccess() }
        hotkey.start()

        setUpStatusItem()

        #if DEBUG
        runDebugArguments()
        #endif
    }

    #if DEBUG
    /// `--dark`, `--show`, `--type <text>`, `--search <query>`, `--flick <n>`
    /// drive the UI for screenshots during development.
    private func runDebugArguments() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if args.contains("--show") { controller.show() }
        if let text = value(after: "--type") { controller.state.query = text }
        if let query = value(after: "--search") { controller.search(query) }
        if let count = value(after: "--flick").flatMap(Int.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [controller] in
                for _ in 0..<count { controller?.browser.step(1) }
            }
        }
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Grover")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Open Grover (fn Space)", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Grover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        accessibilityItem.isHidden = HotkeyMonitor.isTrusted
    }

    @objc private func openPanel() {
        controller.show()
    }

    @objc private func grantAccess() {
        HotkeyMonitor.promptForAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Main menu

    /// An accessory app has no visible menu bar, but the Edit menu's key
    /// equivalents are what make ⌘C / ⌘V / ⌘A / ⌘Z work in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Grover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
