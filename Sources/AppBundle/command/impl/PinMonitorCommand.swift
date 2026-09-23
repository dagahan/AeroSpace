import AppKit
import Common

struct PinMonitorCommand: Command {
    let args: PinMonitorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        switch args.target.val {
            case .off:
                pinnedMonitorKey = nil
                return .succ
            case .monitor(let description):
                guard let monitor = description.resolveMonitor(sortedMonitors: sortedMonitors) else {
                    return .fail(io.err("No monitor matches the pattern"))
                }
                pinnedMonitorKey = monitor.key
                return .succ
        }
    }
}
