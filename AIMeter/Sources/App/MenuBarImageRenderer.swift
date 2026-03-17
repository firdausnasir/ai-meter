import SwiftUI
import AppKit

@MainActor
enum MenuBarImageRenderer {
    static func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let cgImage = renderer.cgImage else { return nil }
        let scale = renderer.scale
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        ))
        nsImage.isTemplate = false
        return nsImage
    }
}
