import Foundation

@MainActor enum BordersSync {
    private static var lastHidden: Bool? = nil
    private static let bordersBin = ["/opt/homebrew/bin/borders", "/usr/local/bin/borders"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    private static let bordersrc = NSString(string: "~/.config/borders/bordersrc").expandingTildeInPath

    static func sync() {
        let hidden = config.floatingWorkspaces.contains(focus.workspace.name)
        if hidden == lastHidden { return }
        lastHidden = hidden
        let proc = Process()
        if hidden {
            guard let bordersBin else { return }
            proc.executableURL = URL(fileURLWithPath: bordersBin)
            proc.arguments = ["width=0.0"]
        } else {
            guard FileManager.default.isExecutableFile(atPath: bordersrc) else { return }
            proc.executableURL = URL(fileURLWithPath: bordersrc)
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env
        try? proc.run()
    }
}
