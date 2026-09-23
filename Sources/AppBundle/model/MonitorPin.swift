import Foundation

let pinDoubleTapInterval: TimeInterval = 0.3

@MainActor var pinnedMonitorKey: String? = nil
@MainActor private var lastLetterTap: (monitorKey: String, at: Date)? = nil

@MainActor var pinnedMonitor: Monitor? {
    pinnedMonitorKey.flatMap { key in monitors.first { $0.key == key } }
}

@MainActor func noteLetterTap(onMonitor key: String, at now: Date = .now) {
    if let previousTap = lastLetterTap, previousTap.monitorKey == key, now.timeIntervalSince(previousTap.at) <= pinDoubleTapInterval {
        pinnedMonitorKey = pinnedMonitorKey == key ? nil : key
        lastLetterTap = nil
    } else {
        lastLetterTap = (key, now)
    }
}

@MainActor func forgetPinForTests() {
    pinnedMonitorKey = nil
    lastLetterTap = nil
}
