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
        didSet { Keychain.set(anthropicAPIKey, for: Keys.anthropicAPIKey) }
    }

    @Published var diarize: Bool {
        didSet { defaults.set(diarize, forKey: Keys.diarize) }
    }

    @Published var launchAtLogin: Bool {
        didSet { LoginItem.setEnabled(launchAtLogin) }
    }

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

    @Published private(set) var outputFolderPath: String?
    @Published private(set) var audioFolderPath: String?

    var hasOutputFolder: Bool { outputFolderPath != nil }

    var keepAudioExplanation: String {
        keepAudio
            ? "After a call is transcribed, its audio files are saved to this folder. Until you choose one, they're kept in Application Support."
            : "Audio is deleted once the note is saved. Turn this on to keep the recordings."
    }

    var outputFolderName: String? {
        outputFolderPath.map { ($0 as NSString).lastPathComponent }
    }

    var audioFolderName: String? {
        audioFolderPath.map { ($0 as NSString).lastPathComponent }
    }

    private let defaults = UserDefaults.standard

    init() {
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

        if let legacyKey = defaults.string(forKey: Keys.anthropicAPIKey), !legacyKey.isEmpty {
            Keychain.set(legacyKey, for: Keys.anthropicAPIKey)
            defaults.removeObject(forKey: Keys.anthropicAPIKey)
            self.anthropicAPIKey = legacyKey
        } else {
            self.anthropicAPIKey = Keychain.get(Keys.anthropicAPIKey) ?? ""
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
        if let url = chooseFolder(prompt: "Choose Vault Folder",
                                  message: "Pick the folder (or Obsidian vault) where notes will be saved.",
                                  bookmarkKey: Keys.outputBookmark) {
            outputFolderPath = url.path
        }
    }

    func chooseAudioFolder() {
        if let url = chooseFolder(prompt: "Choose Audio Folder",
                                  message: "Pick the folder where call audio will be kept.",
                                  bookmarkKey: Keys.audioBookmark) {
            audioFolderPath = url.path
        }
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

        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        defaults.set(data, forKey: key)
    }

    private func chooseFolder(prompt: String, message: String, bookmarkKey: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return nil }
        defaults.set(data, forKey: bookmarkKey)
        return url
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

#if DEBUG
extension Settings {
    func seedForScreenshots(outputFolder: String) { outputFolderPath = outputFolder }
}
#endif
