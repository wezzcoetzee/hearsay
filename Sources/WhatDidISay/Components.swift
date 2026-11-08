import AppKit
import SwiftUI

/// Words shared by more than one surface.
enum Copy {
    static let deleteRecordingConsequence = "The audio is deleted and no note is saved. This can't be undone."
    static let autoDetectExplanation =
        "Offers to record when a Slack huddle, Teams call or Google Meet starts. Nothing records until you click Start Recording on that prompt."
    static let autoDetectNeedsScreenRecording = "Needs Screen Recording, since only calls are detected."
    static let relaunchHint = "Allowed Screen Recording? Relaunch to apply it."
    /// The one moment anything leaves the Mac, worded once wherever it's shown.
    static let cloudBoundary = "Transcript text is sent to Anthropic for the summary. Audio stays on your Mac."

    /// What starting a recording means, said the same way by the call prompt and the
    /// first-recording alert, and true to whether cloud summaries are on.
    static func consent(for source: RecordingSource, cloud: Bool) -> String {
        let who = source.usesSystemAudio ? "Records everyone on the call." : "Records everyone in the room."
        return "\(who) \(cloud ? cloudBoundary : "Audio and transcript stay on your Mac.")"
    }
}

/// Whether a permission is allowed, drawn one way everywhere: the symbol carries the
/// colour, the words stay secondary so they keep their contrast.
struct PermissionStatus: View {
    let name: String
    let allowed: Bool
    /// Asked for, but macOS only reports it after a relaunch: saying "Not allowed" right
    /// after the user allowed it would read as a contradiction.
    var pendingRelaunch = false

    private var text: String {
        if allowed { return "Allowed" }
        return pendingRelaunch ? "Relaunch to apply" : "Not allowed"
    }

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: allowed ? "checkmark.circle.fill" : pendingRelaunch ? "arrow.clockwise.circle" : "circle")
                .foregroundStyle(allowed ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(text.lowercased())")
    }
}

/// A switch at the trailing edge with its label on the left, as in Control Center and
/// System Settings, for places outside a grouped Form.
struct TrailingSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }
}

/// A message with a coloured symbol and readable text: the colour marks the kind of
/// message, the text stays primary so it holds its contrast on any background.
struct Caution: View {
    let text: String
    let symbol: String
    let tint: Color

    init(_ text: String, symbol: String = "exclamationmark.triangle.fill", tint: Color = .orange) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

extension NSImage {
    /// An SF Symbol drawn in the secondary label colour. Menus with a symbol label
    /// ignore SwiftUI's foreground style, so the colour is baked in.
    static func secondarySymbol(_ name: String) -> NSImage {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        let image = base.withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor])) ?? base
        image.isTemplate = false
        return image
    }
}

/// A borderless symbol button with a hit area large enough to land on: the glyphs are
/// small, the target isn't.
struct IconButton: View {
    let symbol: String
    let label: String
    var help: String?
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

/// A chosen folder shown by name (full path on hover) with Change…, or a Choose…
/// button when there's none yet. The one folder control used everywhere.
struct FolderChoice: View {
    let path: String?
    let choose: () -> Void
    /// In a full-width callout, pushes the button to the trailing edge; in a Form row
    /// the row already does that.
    var spread = false

    var body: some View {
        HStack(spacing: 8) {
            if let path {
                Label((path as NSString).lastPathComponent, systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle)
                    .help((path as NSString).abbreviatingWithTildeInPath)
                if spread { Spacer(minLength: 8) }
                Button("Change…", action: choose)
            } else {
                Text("None chosen").foregroundStyle(.secondary)
                Button("Choose…", action: choose)
            }
        }
    }
}

/// Screen Recording only applies after the app restarts, so every place that asks for
/// it offers this, worded and styled the same. Never while recording or making a note:
/// relaunching then would cut the call off without the care Quit takes.
struct RelaunchButton: View {
    var isBusy = false

    var body: some View {
        Button("Relaunch Now") { OnboardingController.relaunch() }
            .disabled(isBusy)
            .help(isBusy ? "Available once the current recording is done." : "")
    }
}
