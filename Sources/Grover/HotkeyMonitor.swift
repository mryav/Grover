import AppKit
import ApplicationServices

/// Listens for fn+Space system-wide. The fn (globe) key isn't a modifier that
/// Carbon hotkeys understand, so this uses a CGEvent tap, which needs the
/// Accessibility permission.
@MainActor
final class HotkeyMonitor {
    var onTrigger: () -> Void = {}

    fileprivate var tap: CFMachPort?
    private var retryTimer: Timer?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Starts the tap, retrying until Accessibility access is granted.
    func start() {
        guard tap == nil else { return }
        if installTap() { return }
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if self.installTap() {
                    timer.invalidate()
                    self.retryTimer = nil
                }
            }
        }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

private let spaceKeyCode: Int64 = 49

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

    // The tap is installed on the main run loop, so this runs on the main thread.
    return MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == spaceKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard flags.contains(.maskSecondaryFn), flags.isDisjoint(with: otherModifiers) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { monitor.onTrigger() }
        }
        // Swallow fn+Space (down, up and repeats) so it doesn't type a space.
        return nil
    }
}
