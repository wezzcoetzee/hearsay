import Testing
@testable import WhatDidISay

@Suite struct RecordingSourceTests {
    @Test func displayNames() {
        #expect(RecordingSource.manual.displayName == "Manual")
        #expect(RecordingSource.slack.displayName == "Slack Huddle")
        #expect(RecordingSource.teams.displayName == "Teams Call")
        #expect(RecordingSource.googleMeet.displayName == "Google Meet")
    }

    @Test func googleMeetCapturesTheHostBrowser() {
        #expect(RecordingSource.googleMeet.bundleIDs.contains("com.google.Chrome"))
        #expect(RecordingSource.googleMeet.bundleIDs.contains("com.apple.Safari"))
    }

    @Test func manualHasNoBundleIDs() {
        #expect(RecordingSource.manual.bundleIDs.isEmpty)
    }

    @Test func detectableExcludesManual() {
        #expect(RecordingSource.detectable == [.slack, .teams])
    }

    @Test func sourceForKnownBundleIDs() {
        #expect(RecordingSource.source(forBundleID: "com.tinyspeck.slackmacgap") == .slack)
        #expect(RecordingSource.source(forBundleID: "com.microsoft.teams2") == .teams)
        #expect(RecordingSource.source(forBundleID: "com.microsoft.teams") == .teams)
    }

    @Test func sourceForUnknownBundleIDIsNil() {
        #expect(RecordingSource.source(forBundleID: "com.apple.Safari") == nil)
        #expect(RecordingSource.source(forBundleID: "") == nil)
    }

    @Test func browsersAreNotMatchedGenerically() {
        for browser in RecordingSource.browserBundleIDs {
            #expect(RecordingSource.source(forBundleID: browser) == nil)
        }
    }
}
