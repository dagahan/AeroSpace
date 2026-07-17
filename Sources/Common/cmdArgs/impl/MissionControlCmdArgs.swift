public struct MissionControlCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .missionControl,
        help: """
            USAGE: mission-control [-h|--help]

            Toggle the workspaces overview overlay
            """,
        flags: [:],
        posArgs: [],
    )
}
