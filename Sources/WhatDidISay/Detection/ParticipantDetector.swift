import Foundation
import ScreenCaptureKit
import Vision
import ApplicationServices
import AppKit
import NaturalLanguage

struct ParticipantDetector: Sendable {
    func detect(targetBundleID: String) async -> Set<String> {
        var names = Set<String>()
        if let pid = await MainActor.run(body: {
            NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first?.processIdentifier
        }) {
            names.formUnion(await Task.detached { Self.accessibilityNames(pid: pid) }.value)
        }
        names.formUnion(await ocrNames(targetBundleID: targetBundleID))
        return names
    }

    // MARK: OCR

    private func ocrNames(targetBundleID: String) async -> Set<String> {
        guard let image = try? await captureImage(targetBundleID: targetBundleID) else { return [] }
        return await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return Self.filterNames(lines)
        }.value
    }

    private func captureImage(targetBundleID: String) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let app = content.applications.first(where: { $0.bundleIdentifier == targetBundleID }),
              let display = content.displays.first else { return nil }

        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: Accessibility

    private static func accessibilityNames(pid: pid_t) -> Set<String> {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var strings: [String] = []
        var budget = 4000
        collect(app, depth: 0, budget: &budget, into: &strings)
        return filterNames(strings)
    }

    private static func collect(_ element: AXUIElement, depth: Int, budget: inout Int, into strings: inout [String]) {
        guard depth < 18, budget > 0 else { return }
        budget -= 1

        if axString(element, kAXRoleAttribute) == (kAXStaticTextRole as String) {
            if let value = axString(element, kAXValueAttribute) { strings.append(value) }
            if let title = axString(element, kAXTitleAttribute) { strings.append(title) }
        }
        for child in axChildren(element) {
            collect(child, depth: depth + 1, budget: &budget, into: &strings)
        }
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

    // MARK: Filtering

    private static let blocklist: Set<String> = [
        "mute", "unmute", "leave", "invite", "share", "huddle", "screen", "camera", "video",
        "settings", "people", "add", "slack", "teams", "microsoft", "join", "chat", "reactions",
        "more", "record", "recording", "speaker", "mic", "microphone", "you", "present", "raise",
        "hand", "participants", "call", "meeting", "end", "hang up", "stop", "start", "on", "off",
        "gallery", "grid", "background", "effects", "device", "audio", "output", "input"
    ]

    static func filterNames(_ lines: [String]) -> Set<String> {
        var result = Set<String>()
        for raw in lines {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2, name.count <= 40 else { continue }
            guard !blocklist.contains(name.lowercased()) else { continue }
            let words = name.split(separator: " ")
            guard (1...3).contains(words.count) else { continue }
            let plausible = words.allSatisfy { word in
                guard let first = word.first, first.isUppercase else { return false }
                return word.allSatisfy { $0.isLetter || $0 == "." || $0 == "'" || $0 == "-" }
            }
            guard plausible, !isCommonPhrase(name) else { continue }
            result.insert(name)
        }
        return result
    }

    private static let lexicalTags: Set<NLTag> = [
        .noun, .verb, .adjective, .adverb, .pronoun, .determiner, .particle,
        .preposition, .number, .conjunction, .interjection, .classifier, .idiom, .otherWord
    ]

    /// True when every token is a common dictionary word, marking UI phrases like
    /// "New Message" or "Meeting Notes" that a person's name never is.
    private static func isCommonPhrase(_ name: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = name
        var tokenCount = 0
        var lexicalCount = 0
        tagger.enumerateTags(
            in: name.startIndex..<name.endIndex,
            unit: .word,
            scheme: .nameTypeOrLexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, _ in
            tokenCount += 1
            if let tag, lexicalTags.contains(tag) { lexicalCount += 1 }
            return true
        }
        return tokenCount > 0 && lexicalCount == tokenCount
    }
}
