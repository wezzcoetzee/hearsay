import SwiftUI
import AppKit
import ApplicationServices

@MainActor
final class ParticipantReviewController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<ReviewedRoster?, Never>?
    private var fallback = ReviewedRoster(voices: [], others: [])

    /// Returns the confirmed roster, or `nil` when the user chooses to delete the call.
    /// Cancelling the calling task closes the dialog and also returns `nil`, so callers
    /// must check for cancellation before treating `nil` as a delete.
    func review(_ request: RosterReview) async -> ReviewedRoster? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.fallback = request.unreviewed
                present(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(with: nil) }
        }
    }

    private func present(_ request: RosterReview) {
        let view = ParticipantReviewView(request: request) { [weak self] roster in
            self?.finish(with: roster)
        } onDelete: { [weak self] in
            self?.finish(with: nil)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: view)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: fallback)
    }

    private func finish(with result: ReviewedRoster?) {
        guard let continuation else { return }
        self.continuation = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        continuation.resume(returning: result)
    }
}

/// One line per voice heard, then names read off the call window, then anyone added
/// by hand. Naming a voice relabels it throughout the transcript; leaving it blank keeps
/// the label. Removing a voice folds its lines into a neighbouring voice, for when
/// diarization split one person in two.
struct ParticipantReviewView: View {
    /// Rows are removable, so they need a stable identity; indexing a shrinking array
    /// from a `ForEach` binding crashes when the last row goes.
    private struct Attendee: Identifiable {
        let id = UUID()
        var name: String
        var included = true
    }

    private let voices: [VoiceCandidate]
    @State private var names: [String]
    @State private var mergedInto: [Int: Int] = [:]
    @State private var detected: [Attendee]
    @State private var added: [Attendee] = []
    @State private var newName = ""
    @State private var confirmingDelete = false
    private let onDone: (ReviewedRoster) -> Void
    private let onDelete: () -> Void
    private let accessibilityTrusted: Bool

    init(request: RosterReview, accessibilityTrusted: Bool = AXIsProcessTrusted(),
         onDone: @escaping (ReviewedRoster) -> Void, onDelete: @escaping () -> Void) {
        self.voices = request.voices
        self.accessibilityTrusted = accessibilityTrusted
        _names = State(initialValue: request.voices.map(\.suggestion))
        _detected = State(initialValue: request.others.map { Attendee(name: $0, included: false) })
        self.onDone = onDone
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who was talking?")
                .font(.headline)
                .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(voices.indices, id: \.self, content: voiceRow)

                    if !detected.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("Seen on screen, not heard. Tick anyone who was there.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach($detected) { $attendee in
                            Toggle(attendee.name, isOn: $attendee.included)
                                .toggleStyle(.checkbox)
                                .foregroundStyle(attendee.included ? .primary : .secondary)
                        }
                    }

                    if !added.isEmpty {
                        Divider().padding(.vertical, 4)
                        ForEach($added) { $attendee in
                            HStack(spacing: 8) {
                                TextField("Name", text: $attendee.name)
                                    .textFieldStyle(.roundedBorder)
                                removeButton(attendee.name.isEmpty ? "Remove participant" : "Remove \(attendee.name)") {
                                    added.removeAll { $0.id == attendee.id }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            HStack {
                TextField("Add someone who didn't speak", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addName)
                Button("Add", action: addName)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if !accessibilityTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Enable Accessibility for better name detection.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Enable") {
                        let options = ["AXTrustedCheckOptionPrompt": true]
                        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Button("Delete Recording", role: .destructive) {
                    confirmingDelete = true
                }
                .confirmationDialog(
                    "Delete this recording?",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Recording", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The recording is discarded and no note is saved. This can't be undone.")
                }
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 380, height: 460)
    }

    @ViewBuilder
    private func voiceRow(_ index: Int) -> some View {
        let voice = voices[index]
        HStack(spacing: 8) {
            Text(voice.label)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
                .accessibilityHidden(true)
            if let target = mergedInto[index] {
                Text("Lines moved to \(displayName(target))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Undo") { mergedInto[index] = nil }
                    .buttonStyle(.link).font(.caption)
            } else {
                // Labelled on the field itself: combining the row would hide the text
                // field from VoiceOver.
                TextField("Name", text: $names[index])
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Name for \(voice.label)")
                    .accessibilityHint("Said: \(voice.sample)")
                if let target = RosterReview.mergeTarget(for: index, in: voices, merged: Set(mergedInto.keys)) {
                    removeButton("Same person as \(displayName(target))") { mergedInto[index] = target }
                        .help("Same person as \(displayName(target))")
                }
            }
        }
        if voice.label != Speaker.me.label, mergedInto[index] == nil {
            Text("\u{201C}\(voice.sample)\u{201D}")
                .font(.caption).italic().foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .padding(.leading, 84)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
        }
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    /// What a voice is called right now, following merges, as shown in the dialog.
    private func displayName(_ index: Int) -> String {
        let name = RosterReview.reviewed(voices, names: names, mergedInto: mergedInto)[index].name
        return name.isEmpty ? voices[index].label : name
    }

    private func addName() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        added.append(Attendee(name: trimmed))
        newName = ""
    }

    private func save() {
        let present = (detected.filter(\.included) + added)
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onDone(ReviewedRoster(
            voices: RosterReview.reviewed(voices, names: names, mergedInto: mergedInto),
            others: present
        ))
    }
}
