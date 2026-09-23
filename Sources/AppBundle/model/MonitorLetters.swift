private let lettersByRowAndMonitorCount: [[String]] = [
    ["d", "df", "sdf", "sdfg"],
    ["c", "cv", "xcv", "xcvb"],
]

func monitorLetters(_ monitors: [Monitor]) -> [String: Character] {
    var rows: [[Monitor]] = []
    for monitor in monitors.filter({ !$0.isStandIn }).sorted(by: { $0.rect.minY < $1.rect.minY }) {
        if let rowIndex = rows.firstIndex(where: { row in row.contains { $0.relation(to: monitor) == .h } }) {
            rows[rowIndex].append(monitor)
        } else {
            rows.append([monitor])
        }
    }
    var letters: [String: Character] = [:]
    for (row, letterSets) in zip(rows, lettersByRowAndMonitorCount) {
        let monitorsLeftToRight = row.sorted(by: { $0.rect.minX < $1.rect.minX }).prefix(letterSets.count)
        let letterSet = letterSets[monitorsLeftToRight.count - 1]
        for (monitor, letter) in zip(monitorsLeftToRight, letterSet) {
            letters[monitor.key] = letter
        }
    }
    return letters
}

extension Monitor {
    var letter: Character? { monitorLetters(monitors)[key] }
}
