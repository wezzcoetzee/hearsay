import Foundation

/// One way of writing elapsed time across the timers and transcript, so a long call
/// reads `1:05:12` instead of `65:12`.
enum ElapsedTime {
    static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }

    /// VoiceOver phrasing, e.g. "1 hour, 5 minutes, 12 seconds".
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
