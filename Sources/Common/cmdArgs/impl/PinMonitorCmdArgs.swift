public struct PinMonitorCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .pinMonitor,
        help: """
            USAGE: pin-monitor [-h|--help] (off|<monitor-pattern>)

            Pin a monitor. While a monitor is pinned, 'move-node-to-workspace <number>' sends the
            window to that number on the pinned monitor instead of on the window's own monitor.
            'off' unpins. Double-tapping 'focus-monitor letter:<x>' pins and unpins too.
            """,
        flags: [:],
        posArgs: [newMandatoryPosArgParser(\.target, parsePinMonitorTarget, placeholder: "(off|<monitor-pattern>)")],
    )

    public var target: Lateinit<PinMonitorTarget> = .uninitialized
}

public enum PinMonitorTarget: Equatable, Sendable {
    case off
    case monitor(MonitorDescription)
}

func parsePinMonitorTarget(i: PosArgParserInput) -> ParsedCliArgs<PinMonitorTarget> {
    i.arg == "off"
        ? .succ(.off, advanceBy: 1)
        : .init(parseMonitorDescription(i.arg).map(PinMonitorTarget.monitor), advanceBy: 1)
}
