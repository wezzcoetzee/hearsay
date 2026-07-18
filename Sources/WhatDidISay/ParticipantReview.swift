import SwiftUI
import AppKit
import ApplicationServices

@MainActor
final class ParticipantReviewController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<[String]?, Never>?
    private var fallback: [String] = []

    /// Returns the confirmed roster, or `nil` when the user chooses to delete the call.
    func review(candidates: [String]) async -> [String]? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.fallback = candidates.isEmpty ? ["Me"] : candidates
            present(candidates: candidates)
        }
    }

    private func present(candidates: [String]) {
        let view = ParticipantReviewView(initial: candidates) { [weak self] result in
            self?.finish(with: result)
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

    private func finish(with result: [String]?) {
        guard let continuation else { return }
        self.continuation = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        continuation.resume(returning: result)
    }
}

struct ParticipantReviewView: View {
    @State private var names: [String]
    @State private var newName = ""
    @State private var confirmingDelete = false
    private let onDone: ([String]) -> Void
    private let onDelete: () -> Void

    init(initial: [String], onDone: @escaping ([String]) -> Void, onDelete: @escaping () -> Void) {
        _names = State(initialValue: initial.isEmpty ? ["Me"] : initial)
        self.onDone = onDone
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who was on the call?")
                    .font(.headline)
                Text("We guessed from the on-screen roster. Correct anything that's wrong before we save the note.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(names.indices, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $names[index])
                                .textFieldStyle(.roundedBorder)
                            Button {
                                names.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(names[index].isEmpty ? "Remove participant" : "Remove \(names[index])")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            HStack {
                TextField("Add participant", text: $newName)
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
                Button("Delete Call", role: .destructive) {
                    confirmingDelete = true
                }
                .confirmationDialog(
                    "Delete this call?",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Call", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The recording is discarded and no note is saved. This can't be undone.")
                }
                Spacer()
                Button("Save") {
                    let cleaned = names
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    onDone(cleaned.isEmpty ? ["Me"] : cleaned)
                }
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
        names.append(trimmed)
        newName = ""
    }
}
