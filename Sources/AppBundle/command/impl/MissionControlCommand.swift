import AppKit
import Common

struct MissionControlCommand: Command {
    let args: MissionControlCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        MissionControl.toggle()
        return .succ
    }
}
