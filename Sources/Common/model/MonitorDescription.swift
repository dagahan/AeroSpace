public enum MonitorDescription: Equatable, Sendable {
    case sequenceNumber(Int)
    case main
    case secondary
    case pattern(CaseInsensitiveRegex)
    case letter(Character)

    public static func pattern(_ raw: String) -> MonitorDescription? {
        switch CaseInsensitiveRegex.new(raw) {
            case .success(let regex): .pattern(regex)
            case .failure: nil
        }
    }
}

private let monitorLetterPrefix = "letter:"

public func parseMonitorDescription(_ raw: String) -> ResOrStr<MonitorDescription> {
    if let int = Int(raw) {
        return int >= 1
            ? .success(.sequenceNumber(int))
            : .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal")
    }
    if raw == "main" {
        return .success(.main)
    }
    if raw == "secondary" {
        return .success(.secondary)
    }
    if raw.hasPrefix(monitorLetterPrefix) {
        let letter = raw.dropFirst(monitorLetterPrefix.count).lowercased()
        return letter.count == 1 && letter.allSatisfy(\.isLetter)
            ? .success(.letter(Character(letter)))
            : .failure("'\(monitorLetterPrefix)' must be followed by exactly one letter")
    }

    return raw.isEmpty
        ? .failure("Empty string is an illegal monitor description")
        : CaseInsensitiveRegex.new(raw).map(MonitorDescription.pattern)
}
