import Foundation
import AppKit
import ApplicationServices

/// Finds a browser that currently has a live Google Meet tab open.
///
/// A running browser is not a call, so — unlike Slack/Teams — the mic going live
/// isn't enough. We inspect each browser's accessibility tree for a tab titled with
/// a Meet meeting code (`abc-defg-hij`), which only appears once you're in (or in the
/// green room of) an actual meeting, not on the meet.google.com landing page.
@MainActor
struct BrowserCallDetector {
    func meetBrowserBundleID() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let running = NSWorkspace.shared.runningApplications
        for bundleID in RecordingSource.browserBundleIDs {
            guard let app = running.first(where: { $0.bundleIdentifier == bundleID }) else { continue }
            if hasMeetTab(pid: app.processIdentifier) { return bundleID }
        }
        return nil
    }

    private static let meetCode = try! NSRegularExpression(
        pattern: "\\b[a-z]{3}-[a-z]{4}-[a-z]{3}\\b"
    )

    private func hasMeetTab(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var budget = 6000
        return search(app, depth: 0, budget: &budget)
    }

    private func search(_ element: AXUIElement, depth: Int, budget: inout Int) -> Bool {
        guard depth < 20, budget > 0 else { return false }
        budget -= 1

        if let title = Self.axString(element, kAXTitleAttribute), Self.isMeetTitle(title) { return true }
        if let value = Self.axString(element, kAXValueAttribute), Self.isMeetTitle(value) { return true }

        for child in Self.axChildren(element) {
            if search(child, depth: depth + 1, budget: &budget) { return true }
        }
        return false
    }

    private static func isMeetTitle(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return meetCode.firstMatch(in: title, range: range) != nil
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }
}
