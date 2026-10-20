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

/// One line per voice heard, plus anyone who was there without speaking. Naming a
/// voice relabels it throughout the transcript; leaving it blank keeps the label.
struct ParticipantReviewView: View {
    /// Rows are removable, so they need a stable identity; indexing a shrinking array
    /// from a `ForEach` binding crashes when the last row goes.
    private struct Attendee: Identifiable {
        let id = UUID()
        var name: String
    }

    private let voices: [VoiceCandidate]
    @State private var names: [String]
    @State private var others: [Attendee]
    @State private var newName = ""
    @State private var confirmingDelete = false
    private let onDone: (ReviewedRoster) -> Void
    private let onDelete: () -> Void

    init(request: RosterReview, onDone: @escaping (ReviewedRoster) -> Void, onDelete: @escaping () -> Void) {
        self.voices = request.voices
        _names = State(initialValue: request.voices.map(\.suggestion))
        _others = State(initialValue: request.others.map { Attendee(name: $0) })
        self.onDone = onDone
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who was talking?")
                    .font(.headline)
                Text("Voices you don't name keep their label in the note.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(voices.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text(voices[index].label)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 76, alignment: .leading)
                                .help(voices[index].sample)
                                .accessibilityHidden(true)
                            // Labelled on the field itself: combining the row would hide
                            // the text field from VoiceOver.
                            TextField("Name", text: $names[index])
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Name for \(voices[index].label)")
                                .accessibilityHint("Said: \(voices[index].sample)")
                        }
                    }

                    if !others.isEmpty {
                        Divider().padding(.vertical, 4)
                        ForEach($others) { $attendee in
                            HStack(spacing: 8) {
                                TextField("Name", text: $attendee.name)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    others.removeAll { $0.id == attendee.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(attendee.name.isEmpty ? "Remove participant" : "Remove \(attendee.name)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            HStack {
                TextField("Someone who didn't speak", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addName)
                Button("Add", action: addName)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if !AXIsProcessTrusted() {
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

    private func addName() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        others.append(Attendee(name: trimmed))
        newName = ""
    }

    private func save() {
        let reviewed = zip(voices, names).map {
            ReviewedVoice(label: $0.label, name: $1.trimmingCharacters(in: .whitespaces))
        }
        let present = others
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onDone(ReviewedRoster(voices: reviewed, others: present))
    }
}
