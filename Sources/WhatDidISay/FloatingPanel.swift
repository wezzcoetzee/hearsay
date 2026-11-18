import AppKit

extension NSPanel {
    /// A panel that floats over every Space, full-screen apps included, without taking
    /// focus from the call, placed in the bottom-right corner of the main screen: the
    /// top-right is where notification banners (a call app's own included) land.
    static func floating(contentView: NSView, size: NSSize, styleMask: NSWindow.StyleMask) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask.union([.nonactivatingPanel, .fullSizeContentView]),
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = contentView

        if let screen = NSScreen.main?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24,
                                         y: screen.minY + 24))
        }
        return panel
    }
}
