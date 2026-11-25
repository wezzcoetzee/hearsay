import Testing

@testable import Hearsay

@MainActor
@Suite struct CallDetectorSourceOrderTests {
    /// Records which checks ran, so tests can assert the cheap ones short-circuit the costly ones.
    private func resolve(
        frontmost: RecordingSource? = nil,
        meetTab: Bool = false,
        background: RecordingSource? = nil
    ) async -> (source: RecordingSource?, checked: [String]) {
        var checked: [String] = []
        let source = await CallDetector.resolveSource(
            frontmost: frontmost,
            hasMeetTab: {
                checked.append("meet"); return meetTab
            },
            backgroundCallApp: {
                checked.append("background"); return background
            }
        )
        return (source, checked)
    }

    @Test func frontmostCallAppWinsWithoutFurtherChecks() async {
        let result = await resolve(frontmost: .teams, meetTab: true, background: .slack)
        #expect(result.source == .teams)
        #expect(result.checked.isEmpty)
    }

    @Test func meetTabBeatsABackgroundCallApp() async {
        let result = await resolve(meetTab: true, background: .slack)
        #expect(result.source == .googleMeet)
        #expect(result.checked == ["meet"])
    }

    @Test func backgroundCallAppIsTheLastResort() async {
        let result = await resolve(background: .slack)
        #expect(result.source == .slack)
        #expect(result.checked == ["meet", "background"])
    }

    @Test func nothingMatchingYieldsNoSource() async {
        #expect(await resolve().source == nil)
    }
}
