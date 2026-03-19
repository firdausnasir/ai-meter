import AppKit
import SwiftUI

// Dedicated recap window — opened separately from the popover, never reuses the main panel.
final class RecapWindowController: NSWindowController {
    private static var instance: RecapWindowController?
    private static var hostingView: NSHostingView<RecapView>?

    static func show(recap: MonthlyRecapData) {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Replace content with fresh data
            hostingView?.rootView = RecapView(recap: recap)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Monthly Recap"
        window.isReleasedWhenClosed = false
        // Non-resizable
        window.styleMask.remove(.resizable)
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        window.center()

        let hosting = NSHostingView(rootView: RecapView(recap: recap))
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 640)
        window.contentView = hosting
        hostingView = hosting

        let controller = RecapWindowController(window: window)
        instance = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
