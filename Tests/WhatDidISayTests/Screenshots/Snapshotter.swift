import AppKit
import SwiftUI

/// Renders a SwiftUI view to a PNG without putting a window on screen, so it needs no
/// permissions and never interrupts you. The view is hosted in a real (never shown)
/// window, so AppKit-backed controls draw as they do in the app. One known gap:
/// switches keep their unfocused grey track when on, because their fill comes from the
/// window server's real focus state; the knob position still shows the state.
@MainActor
enum Snapshotter {
    struct Shot {
        let png: Data
        /// Size in points; the PNG is at the screen's backing scale.
        let size: CGSize
    }

    static func render<V: View>(_ view: V, appearance: NSAppearance.Name,
                                scrolledToBottom: Bool = false) async throws -> Shot {
        // Must run before anything touches `NSApplication.shared`, so NSApp is this subclass.
        _ = ActiveApplication.shared
        let host = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.controlActiveState, .key))
        let window = ActiveWindow(contentRect: .zero, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host

        host.layoutSubtreeIfNeeded()
        window.setContentSize(host.fittingSize)
        if scrolledToBottom { scrollToBottom(in: host) }
        // One pass of the run loop lets onAppear and the first TimelineView tick land.
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.noImage }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.noImage }
        return Shot(png: png, size: host.bounds.size)
    }

    private static func scrollToBottom(in view: NSView) {
        for scroll in view.descendants(of: NSScrollView.self) {
            guard let document = scroll.documentView else { continue }
            document.layoutSubtreeIfNeeded()
            let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    enum SnapshotError: Error {
        case noImage
    }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { ($0 as? T).map { [$0] } ?? [] } + subviews.flatMap { $0.descendants(of: type) }
    }
}

/// Prominent buttons draw their inactive (grey) look unless the app is frontmost and
/// the window key. The test runner is neither, and activating it would steal focus,
/// so both just claim to be.
private final class ActiveApplication: NSApplication {
    override var isActive: Bool { true }
}

private final class ActiveWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
