import Common

extension MonitorDescription {
    @MainActor func resolveMonitor(sortedMonitors: [Monitor]) -> Monitor? {
        switch self {
            case .sequenceNumber(let number): sortedMonitors.getOrNil(atIndex: number - 1)
            case .main: mainMonitor
            case .pattern(let regex): sortedMonitors.first { $0.name.contains(caseInsensitiveRegex: regex) }
            case .letter(let letter):
                monitorLetters(sortedMonitors).first { $0.value == letter }
                    .flatMap { match in sortedMonitors.first { $0.key == match.key } }
            case .secondary:
                sortedMonitors.takeIf { $0.count == 2 }?
                    .first { $0.rect.topLeftCorner != mainMonitor.rect.topLeftCorner }
        }
    }
}
