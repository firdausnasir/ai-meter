import AppKit

/// Registers a global keyboard shortcut (⌃⌥A) to toggle the menu bar popover.
/// Uses NSStatusBar to find the app's status item rather than relying on
/// internal SwiftUI MenuBarExtra implementation details.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isHotKey(event) else { return }
            Task { @MainActor in
                self.togglePopover()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isHotKey(event) else { return event }
            self.togglePopover()
            return nil // consume the event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func isHotKey(_ event: NSEvent) -> Bool {
        // ⌃⌥A: keyCode 0 = 'a'
        let required: NSEvent.ModifierFlags = [.control, .option]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == required && event.keyCode == 0
    }

    private func togglePopover() {
        // SwiftUI's MenuBarExtra window has a delegate that owns the NSStatusItem.
        // We reach the button by finding the NSStatusBarButton in any window's subviews.
        for window in NSApp.windows {
            if let button = findStatusBarButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = findStatusBarButton(in: subview) { return found }
        }
        return nil
    }
}
