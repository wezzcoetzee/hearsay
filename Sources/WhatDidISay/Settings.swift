import Foundation
import Combine
import AppKit

@MainActor
final class Settings: ObservableObject {
    private enum Keys {
        static let model = "whisperModel"
        static let outputBookmark = "outputFolderBookmark"
        static let summaryEnabled = "summaryEnabled"
        static let summaryBackend = "summaryBackend"
        static let autoDetect = "autoDetectEnabled"
        static let localSummaryModel = "localSummaryModel"
        static let anthropicAPIKey = "anthropicAPIKey"
        static let diarize = "diarizeEnabled"
        static let keepAudio = "keepAudioEnabled"
        static let audioBookmark = "audioFolderBookmark"
        static let audioFilenameFormat = "audioFilenameFormat"
        static let acknowledgedConsent = "acknowledgedRecordingConsent"
        static let acknowledgedCloud = "acknowledgedCloudSummary"
        static let showRecordingPanel = "showRecordingPanel"
        static let completedOnboarding = "completedOnboarding"
    }

    static let availableModels = ["tiny", "base", "small", "large-v3"]
    static let defaultAudioFilenameFormat = "{date} {time} {source} {track}"

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var summaryEnabled: Bool {
        didSet { defaults.set(summaryEnabled, forKey: Keys.summaryEnabled) }
    }

    @Published var summaryBackend: SummaryBackend {
        didSet { defaults.set(summaryBackend.rawValue, forKey: Keys.summaryBackend) }
    }

    @Published var autoDetect: Bool {
        didSet { defaults.set(autoDetect, forKey: Keys.autoDetect) }
    }

    @Published var localSummaryModel: String {
        didSet { defaults.set(localSummaryModel, forKey: Keys.localSummaryModel) }
    }

    @Published var anthropicAPIKey: String {
        didSet { keychain.set(anthropicAPIKey, for: Keys.anthropicAPIKey) }
    }

    @Published var diarize: Bool {
        didSet { defaults.set(diarize, forKey: Keys.diarize) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            // macOS can refuse; show what actually happened rather than what was asked,
            // and say so, rather than letting the switch silently snap back.
            let registered = LoginItem.setEnabled(launchAtLogin)
            launchAtLoginRefused = registered != launchAtLogin
            if registered != launchAtLogin { launchAtLogin = registered }
        }
    }

    @Published private(set) var launchAtLoginRefused = false

    @Published var hasAcknowledgedConsent: Bool {
        didSet { defaults.set(hasAcknowledgedConsent, forKey: Keys.acknowledgedConsent) }
    }

    @Published var hasAcknowledgedCloud: Bool {
        didSet { defaults.set(hasAcknowledgedCloud, forKey: Keys.acknowledgedCloud) }
    }

    @Published var keepAudio: Bool {
        didSet { defaults.set(keepAudio, forKey: Keys.keepAudio) }
    }

    @Published var audioFilenameFormat: String {
        didSet { defaults.set(audioFilenameFormat, forKey: Keys.audioFilenameFormat) }
    }

    @Published var showRecordingPanel: Bool {
        didSet { defaults.set(showRecordingPanel, forKey: Keys.showRecordingPanel) }
    }

    /// Set when the user finishes the setup guide, so someone who deliberately skips
    /// Screen Recording (to record only the room) isn't walked through it every launch.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.completedOnboarding) }
    }

    @Published private(set) var outputFolderPath: String?
    @Published private(set) var audioFolderPath: String?

    var hasOutputFolder: Bool { outputFolderPath != nil }

    var keepAudioExplanation: String {
        switch (keepAudio, audioFolderName) {
        case (false, _): "Audio is deleted once the note is saved."
        case (true, let folder?): "The audio is moved to \(folder)."
        case (true, nil): "Choose a folder for the audio. Until then it's kept in the app's own Library folder."
        }
    }

    /// True only when a transcript will actually be sent: cloud chosen *and* a key to
    /// send it with. Without a key the summary is skipped, so consent copy mustn't
    /// claim otherwise.
    var cloudSummaryActive: Bool {
        summaryEnabled && summaryBackend == .cloud && !anthropicAPIKey.isEmpty
    }

    var outputFolderName: String? {
        outputFolderPath.map { ($0 as NSString).lastPathComponent }
    }

    var audioFolderName: String? {
        audioFolderPath.map { ($0 as NSString).lastPathComponent }
    }

    private let defaults: UserDefaults
    private let keychain: Keychain

    /// Tests and screenshots pass their own stores so they never read or write the
    /// user's real preferences or API key.
    init(defaults: UserDefaults = .standard, keychain: Keychain = .app) {
        self.defaults = defaults
        self.keychain = keychain
        self.model = defaults.string(forKey: Keys.model) ?? "small"
        self.summaryEnabled = defaults.bool(forKey: Keys.summaryEnabled)
        self.summaryBackend = SummaryBackend(rawValue: defaults.string(forKey: Keys.summaryBackend) ?? "") ?? .local
        self.autoDetect = defaults.bool(forKey: Keys.autoDetect)
        self.localSummaryModel = defaults.string(forKey: Keys.localSummaryModel) ?? "llama3.2"
        self.diarize = defaults.bool(forKey: Keys.diarize)
        self.keepAudio = defaults.bool(forKey: Keys.keepAudio)
        self.audioFilenameFormat = defaults.string(forKey: Keys.audioFilenameFormat) ?? Self.defaultAudioFilenameFormat
        self.showRecordingPanel = defaults.object(forKey: Keys.showRecordingPanel) as? Bool ?? true
        self.launchAtLogin = LoginItem.isEnabled
        self.hasAcknowledgedConsent = defaults.bool(forKey: Keys.acknowledgedConsent)
        self.hasAcknowledgedCloud = defaults.bool(forKey: Keys.acknowledgedCloud)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.completedOnboarding)

        if let legacyKey = defaults.string(forKey: Keys.anthropicAPIKey), !legacyKey.isEmpty {
            // Only drop the old copy once the keychain has it, or the key is lost.
            if keychain.set(legacyKey, for: Keys.anthropicAPIKey) {
                defaults.removeObject(forKey: Keys.anthropicAPIKey)
            }
            self.anthropicAPIKey = legacyKey
        } else {
            self.anthropicAPIKey = keychain.get(Keys.anthropicAPIKey) ?? ""
        }

        self.outputFolderPath = resolveOutputFolder()?.path
        self.audioFolderPath = resolveAudioFolder()?.path
    }

    func resolveOutputFolder() -> URL? {
        resolveFolder(bookmarkKey: Keys.outputBookmark)
    }

    func resolveAudioFolder() -> URL? {
        resolveFolder(bookmarkKey: Keys.audioBookmark)
    }

    /// Re-resolves both bookmarks, so a folder deleted since launch shows as unset and
    /// the UI prompts for a new one instead of claiming it's still there.
    func revalidateFolders() {
        outputFolderPath = resolveOutputFolder()?.path
        audioFolderPath = resolveAudioFolder()?.path
    }

    func chooseOutputFolder() {
        if let url = pickFolder(prompt: "Choose",
                                message: "Choose the notes folder (or Obsidian vault) where each call is saved.") {
            useOutputFolder(url)
        }
    }

    func chooseAudioFolder() {
        if let url = pickFolder(prompt: "Choose",
                                message: "Choose the folder where call audio is kept.") {
            useAudioFolder(url)
        }
    }

    func useOutputFolder(_ url: URL) {
        if storeBookmark(for: url, key: Keys.outputBookmark) { outputFolderPath = url.path }
    }

    func useAudioFolder(_ url: URL) {
        if storeBookmark(for: url, key: Keys.audioBookmark) { audioFolderPath = url.path }
    }

    private func resolveFolder(bookmarkKey: String) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        if stale {
            refreshBookmark(for: url, key: bookmarkKey)
        }
        return url
    }

    private func refreshBookmark(for url: URL, key: String) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        _ = storeBookmark(for: url, key: key)
    }

    private func pickFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func storeBookmark(for url: URL, key: String) -> Bool {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

enum SummaryBackend: String, CaseIterable {
    case local
    case cloud

    var displayName: String {
        switch self {
        case .local: return "Local (Ollama)"
        case .cloud: return "Cloud (Anthropic)"
        }
    }
}
