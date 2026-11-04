import AppKit
import ApplicationServices
import Foundation

/// Finds a browser that currently has a live Google Meet tab open.
///
/// A running browser is not a call, so — unlike Slack/Teams — the mic going live
/// isn't enough. We inspect each browser's accessibility tree for a tab titled with
/// a Meet meeting code (`abc-defg-hij`), which only appears once you're in (or in the
/// green room of) an actual meeting, not on the meet.google.com landing page.
struct BrowserCallDetector: Sendable {
    /// Walks thousands of accessibility elements, so it runs off the main actor.
    func meetBrowserBundleID() async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let browsers = await MainActor.run {
            let running = NSWorkspace.shared.runningApplications
            return RecordingSource.browserBundleIDs.compactMap { bundleID in
                running.first { $0.bundleIdentifier == bundleID }.map { (bundleID, $0.processIdentifier) }
            }
        }
        return await Task.detached {
            browsers.first { Self.hasMeetTab(pid: $0.1) }?.0
        }.value
    }

    private static let meetCode = try! NSRegularExpression(
        pattern: "\\b[a-z]{3}-[a-z]{4}-[a-z]{3}\\b"
    )

    private static func hasMeetTab(pid: pid_t) -> Bool {
        AccessibilityTree.walk(from: AXUIElementCreateApplication(pid), maxDepth: 20, budget: 6000) { element in
            [kAXTitleAttribute, kAXValueAttribute].contains { attribute in
                AccessibilityTree.string(element, attribute).map(isMeetTitle) ?? false
            }
        }
    }

    private static func isMeetTitle(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return meetCode.firstMatch(in: title, range: range) != nil
    }
}
