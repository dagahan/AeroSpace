import AppKit
import Common

struct CloseCommand: Command {
    let args: CloseCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err("Empty workspace"))
        }
        // AX window count is unreliable for Electron apps (phantom AX windows), so count the
        // windows AeroSpace itself tracks (workspaces + minimized), matching the mission-control model.
        let isFinder = window.macAppUnsafe.nsApp.bundleIdentifier == "com.apple.finder"
        let trackedAppWindows = MacWindow.allWindows
            .filter { $0.app.pid == window.app.pid && !($0.parent is MacosPopupWindowsContainer) }
            .count
        if args.quitIfLastWindow, !isFinder, trackedAppWindows <= 1 {
            let app = window.macAppUnsafe
            if app.nsApp.terminate() {
                for workspace in Workspace.all {
                    for window in workspace.allLeafWindowsRecursive where window.app.pid == app.pid {
                        (window as! MacWindow).garbageCollect(skipClosedWindowsCache: true)
                    }
                }
                return .succ
            } else {
                return .fail(io.err("Failed to quit '\(window.app.name ?? "Unknown app")'"))
            }
        } else {
            window.closeAxWindow()
            return .succ
        }
    }
}
