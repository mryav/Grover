import AppKit
import SwiftUI

/// Borderless floating panel that can take keyboard focus without activating
/// the app, like Spotlight.
final class GroverPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.compactSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        // Dragging is handled explicitly by WindowDragArea so text selection
        // and web content never move the window by accident.
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PanelController {
    let panel = GroverPanel()
    private var keyMonitor: Any?
    private var resignObserver: Any?
    private var hasBeenPositioned = false

    var isVisible: Bool { panel.isVisible }

    init(app: AppController) {
        let hosting = NSHostingView(rootView: RootView().environment(app))
        hosting.sizingOptions = []
        panel.contentView = hosting

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak app] _ in
            MainActor.assumeIsolated { app?.panelDidResignKey() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak app, weak panel] event in
            guard let app, let panel, event.window === panel else { return event }
            return app.handleKey(event) ? nil : event
        }
    }

    func show(mode: Mode) {
        if !hasBeenPositioned {
            positionInitially()
            hasBeenPositioned = true
        }
        panel.setFrame(frame(for: mode), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func apply(_ mode: Mode, animated: Bool) {
        let target = frame(for: mode)
        guard panel.isVisible, animated else {
            panel.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [panel] in
            panel.invalidateShadow()
        }
    }

    static func size(for mode: Mode) -> NSSize {
        switch mode {
        case .compact: Theme.compactSize
        case .expanded: Theme.expandedSize
        case .split: Theme.splitSize
        }
    }

    /// Grows from the bottom-left corner so the search bar stays where it is,
    /// then nudges the frame back onto the screen if needed.
    private func frame(for mode: Mode) -> NSRect {
        var frame = NSRect(origin: panel.frame.origin, size: Self.size(for: mode))
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    /// First appearance: centred horizontally, in the lower third of the screen
    /// with the mouse.
    private func positionInitially() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - Theme.compactSize.width / 2,
            y: visible.minY + visible.height * 0.25
        )
        panel.setFrameOrigin(origin)
    }
}
