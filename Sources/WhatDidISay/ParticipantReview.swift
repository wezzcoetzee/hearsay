import SwiftUI
import AppKit
import ApplicationServices

@MainActor
final class ParticipantReviewController: NSObject, NSWindowDelegate {
    /// Set by AppCoordinator: parks the recording under Needs Attention to name later.
    var onNameLater: (() -> Void)?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<ReviewedRoster?, Never>?
    private var fallback = ReviewedRoster(voices: [], others: [])
    /// What the user had typed when they chose Name Later, by recording, so coming
    /// back to name the speakers picks up where they left off. Kept until quit.
    private var drafts: [String: ReviewDraft] = [:]
    private var current: (key: String, draft: ReviewDraft?)?

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
        let key = request.draftKey
        current = (key, drafts[key])
        let view = ParticipantReviewView(request: request, draft: drafts[key]) { [weak self] roster in
            self?.drafts[key] = nil
            self?.finish(with: roster)
        } onDelete: { [weak self] in
            self?.drafts[key] = nil
            self?.finish(with: nil)
        } onNameLater: { [weak self] in
            self?.nameLater()
        } onDraftChange: { [weak self] draft in
            self?.current?.draft = draft
        }
        let hosting = NSHostingView(rootView: view)
        // Sized to what it holds, up to most of the screen; past that the voices scroll.
        let cap = (NSScreen.main?.visibleFrame.height ?? 800) * 0.8
        let size = NSSize(width: hosting.fittingSize.width, height: min(hosting.fittingSize.height, cap))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            // Closing means Name Later: the one way out that neither saves half-named
            // nor deletes.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Who was talking?"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // A normal window that follows the user to whichever Space they're on, so it
        // can't be stranded behind a full-screen app while the pipeline waits on it.
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(size)
        window.center()
        self.window = window
        // Shown without taking focus: it can appear minutes after the call, while the
        // user is typing elsewhere. A click, or Review… in the menu, makes it key.
        window.orderFrontRegardless()
        Announcer.post("Name the speakers from your \(request.context.isEmpty ? "last recording" : request.context). Review is in the \(AppInfo.displayName) menu.")
    }

    /// Brings the waiting review forward, for the menu's Review button.
    func bringToFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// If the window closes some other way (the app quitting), the call is kept: the
    /// note is saved with the voices unnamed, as if nobody had reviewed it.
    /// The close button (and Esc) put the review off rather than closing the window
    /// directly; parking the recording cancels the review, which takes the window down.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        nameLater()
        return false
    }

    /// Keeps what was typed, then parks the recording, which takes the window down.
    private func nameLater() {
        if let current { drafts[current.key] = current.draft }
        onNameLater?()
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
/// the label. "Same person" folds a voice's lines into a neighbouring voice, for when
/// diarization split one person in two.
struct ParticipantReviewView: View {
    static let width: CGFloat = 420

    private enum Field: Hashable {
        case voice(Int)
        case newName
    }

    /// Rows are removable, so they need a stable identity; indexing a shrinking array
    /// from a `ForEach` binding crashes when the last row goes.
    private struct Attendee: Identifiable {
        let id = UUID()
        var name: String
        var included = true
    }

    private let voices: [VoiceCandidate]
    private let context: String
    @FocusState private var focus: Field?
    @State private var names: [String]
    @State private var mergedInto: [Int: Int] = [:]
    @State private var detected: [Attendee]
    @State private var added: [Attendee] = []
    @State private var newName = ""
    @State private var confirmingDelete = false
    private let onDone: (ReviewedRoster) -> Void
    private let onDelete: () -> Void
    private let onNameLater: () -> Void
    private let onDraftChange: (ReviewDraft) -> Void
    /// Re-read when the app comes back from System Settings, so the hint goes away
    /// once Accessibility is allowed.
    @State private var accessibilityTrusted: Bool

    init(request: RosterReview, draft: ReviewDraft? = nil, accessibilityTrusted: Bool = AXIsProcessTrusted(),
         onDone: @escaping (ReviewedRoster) -> Void, onDelete: @escaping () -> Void,
         onNameLater: @escaping () -> Void = {}, onDraftChange: @escaping (ReviewDraft) -> Void = { _ in }) {
        self.voices = request.voices
        self.context = request.context
        _accessibilityTrusted = State(initialValue: accessibilityTrusted)
        let draft = draft.flatMap { $0.names.count == request.voices.count ? $0 : nil }
        _names = State(initialValue: draft?.names ?? request.voices.map(\.suggestion))
        _mergedInto = State(initialValue: draft?.mergedInto ?? [:])
        _detected = State(initialValue: request.others.map {
            Attendee(name: $0, included: draft?.includedSeen.contains($0) ?? false)
        })
        _added = State(initialValue: (draft?.added ?? []).map { Attendee(name: $0) })
        _newName = State(initialValue: draft?.newName ?? "")
        self.onDone = onDone
        self.onDelete = onDelete
        self.onNameLater = onNameLater
        self.onDraftChange = onDraftChange
    }

    /// Everything typed or chosen so far, handed up as it changes so Name Later (or
    /// the close button) can keep it.
    private var draft: ReviewDraft {
        ReviewDraft(names: names, mergedInto: mergedInto, added: added.map(\.name),
                    includedSeen: Set(detected.filter(\.included).map(\.name)), newName: newName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Who was talking?")
                    .font(.headline)
                if !context.isEmpty {
                    Text(context)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Divider()

            // Fits its content when it can; scrolls only when the voices outgrow the window.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }


            if !accessibilityTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Allow Accessibility to read names off the call window.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow…") { PermissionsManager.requestAccessibility() }
                        .controlSize(.small)
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
                    Text(Copy.deleteRecordingConsequence)
                }
                Spacer()
                // What's typed is kept for when the review comes back. Esc only means
                // Name Later outside a field, where it can't be a slip mid-name.
                Button("Name Later", action: onNameLater)
                    .keyboardShortcut(focus == nil ? .cancelAction : nil)
                    .help("Keep the recording under Needs Attention, and what you've typed, to finish later.")
                // Return in a field moves to the next one rather than saving with
                // the rest unnamed, so Save only takes Return when no field is active.
                Button("Save Note", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(focus == nil ? .defaultAction : KeyboardShortcut(.return, modifiers: .command))
                    .help("Save Note (⌘↩)")
            }
            .padding(20)
        }
        .frame(width: Self.width)
        .onChange(of: draft) { _, draft in onDraftChange(draft) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = PermissionsManager.accessibilityTrusted
        }
        // Start in the first name to fill, so Return walks the fields instead of
        // saving a note the moment the window appears.
        .onAppear { focus = voices.indices.first { voices[$0].isPlaceholder && names[$0].isEmpty }.map(Field.voice) }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(voices.indices, id: \.self, content: voiceRow)

            if !detected.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Seen on screen, not heard. Tick anyone who was there.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach($detected) { $attendee in
                    Toggle(attendee.name, isOn: $attendee.included)
                        .toggleStyle(.checkbox)
                }
            }

            if !added.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach($added) { $attendee in
                    HStack(spacing: 8) {
                        TextField("Name", text: $attendee.name)
                            .textFieldStyle(.roundedBorder)
                        IconButton(symbol: "minus.circle",
                                   label: attendee.name.isEmpty ? "Remove participant" : "Remove \(attendee.name)",
                                   help: "Remove") {
                            added.removeAll { $0.id == attendee.id }
                        }
                    }
                }
            }

            // With the people it adds to, not pinned below the empty space.
            HStack {
                TextField("Add someone who didn't speak", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .newName)
                    // Return on an empty add field leaves the fields, so the
                    // next Return is Save Note.
                    .onSubmit {
                        if newName.trimmingCharacters(in: .whitespaces).isEmpty { focus = nil } else { addName() }
                    }
                Button("Add", action: addName)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func voiceRow(_ index: Int) -> some View {
        let voice = voices[index]
        HStack(spacing: 8) {
            // A form's labels: right-aligned against the fields they name.
            Text(voice.label)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 76, alignment: .trailing)
                .accessibilityHidden(true)
            if let target = mergedInto[index] {
                Text("Lines moved to \(displayName(target))")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Undo") { mergedInto[index] = nil }
                    .controlSize(.small)
            } else {
                // Labelled on the field itself: combining the row would hide the text
                // field from VoiceOver.
                TextField("Name", text: $names[index])
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .voice(index))
                    .onSubmit { focus = nextField(after: index) }
                    .accessibilityLabel("Name for \(voice.label)")
                    .accessibilityHint("Said: \(voice.sample)")
                voiceOptions(index)
            }
        }
        if voice.label != Speaker.me.label, mergedInto[index] == nil {
            Text("\u{201C}\(voice.sample)\u{201D}")
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 84)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
        }
    }

    /// One menu per voice for everything besides typing a name: a name read off the
    /// call window, or "this is the same person as another voice" for when diarization
    /// split one speaker in two. Its items say what each does, so no bare glyph has to.
    @ViewBuilder
    private func voiceOptions(_ index: Int) -> some View {
        let voice = voices[index]
        let seen = voice.label == Speaker.me.label ? [] : detected
        let target = RosterReview.mergeTarget(for: index, in: voices, merged: Set(mergedInto.keys))
        if !seen.isEmpty || target != nil {
            Menu {
                if !seen.isEmpty {
                    Section("Seen on Screen") {
                        ForEach(seen) { attendee in
                            Button(attendee.name) { names[index] = attendee.name }
                        }
                    }
                }
                if let target {
                    Section {
                        Button("Same Person as \(displayName(target))") { mergedInto[index] = target }
                    }
                }
            } label: {
                Image(nsImage: .secondarySymbol("ellipsis.circle"))
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Name options")
            .accessibilityLabel("Options for \(voice.label)")
        }
    }

    /// The next voice still waiting for a name, then the add field.
    private func nextField(after index: Int) -> Field {
        voices.indices.dropFirst(index + 1)
            .first { mergedInto[$0] == nil }
            .map(Field.voice) ?? .newName
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
        // A name typed in the add field but never added still counts.
        addName()
        let voiceNames = Set(names.map { $0.trimmingCharacters(in: .whitespaces) })
        // A seen name given to a voice is already a participant; don't list it twice.
        let present = (detected.filter(\.included) + added)
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !voiceNames.contains($0) }
        onDone(ReviewedRoster(
            voices: RosterReview.reviewed(voices, names: names, mergedInto: mergedInto),
            others: present
        ))
    }
}

/// A review in progress, kept when the user chooses Name Later.
struct ReviewDraft: Equatable {
    var names: [String]
    var mergedInto: [Int: Int]
    var added: [String]
    var includedSeen: Set<String>
    var newName: String
}

extension RosterReview {
    /// Identifies the recording a draft belongs to.
    var draftKey: String { context + "|" + voices.map(\.label).joined(separator: ",") }
}
