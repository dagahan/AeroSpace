import Foundation

@MainActor enum BordersSync {
    private static var lastHidden: Bool? = nil

    static func sync() {
        let hidden = config.floatingWorkspaces.contains(focus.workspace.name)
        if hidden == lastHidden { return }
        lastHidden = hidden
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/borders")
        proc.arguments = [hidden ? "width=0.0" : "width=6.0"]
        try? proc.run()
    }
}
