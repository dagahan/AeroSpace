private let lettersByRowAndMonitorCount: [[String]] = [
    ["d", "df", "sdf", "sdfg"],
    ["c", "cv", "xcv", "xcvb"],
]

func monitorLetters(_ monitors: [Monitor]) -> [String: Character] {
    Dictionary(monitorsInLetterOrder(monitors).map { ($0.monitor.key, $0.letter) }, uniquingKeysWith: { first, _ in first })
}

func monitorsInLetterOrder(_ monitors: [Monitor]) -> [(monitor: Monitor, letter: Character)] {
    var rows: [[Monitor]] = []
    for monitor in monitors.filter({ !$0.isStandIn }).sorted(by: { $0.rect.minY < $1.rect.minY }) {
        if let rowIndex = rows.firstIndex(where: { row in row.contains { $0.relation(to: monitor) == .h } }) {
            rows[rowIndex].append(monitor)
        } else {
            rows.append([monitor])
        }
    }
    var lettered: [(monitor: Monitor, letter: Character)] = []
    for (row, letterSets) in zip(rows, lettersByRowAndMonitorCount) {
        let monitorsLeftToRight = row.sorted(by: { $0.rect.minX < $1.rect.minX }).prefix(letterSets.count)
        let letterSet = letterSets[monitorsLeftToRight.count - 1]
        lettered += zip(monitorsLeftToRight, letterSet).map { (monitor: $0, letter: $1) }
    }
    return lettered
}

extension Monitor {
    var letter: Character? { monitorLetters(monitors)[key] }
}
