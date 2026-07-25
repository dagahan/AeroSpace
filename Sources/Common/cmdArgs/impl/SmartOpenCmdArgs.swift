public struct SmartOpenCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .smartOpen,
        help: """
            USAGE: smart-open [-h|--help] <app-name>

            Open <app-name>, but be smart about an already-running app:
              - not running                       -> launch it
              - running and can make a new window -> open a new window on the current workspace
              - running and single-window         -> focus the existing window (switch workspace)

            "Can make a new window" is detected from the app's own menu bar: a ⌘N item whose
            title contains the localized word for "window" (taken from the app's Window menu).
            Apps whose ⌘N does something else — Spotify's New Playlist, VS Code's New Text
            File — fall back to switching. Apps listed in 'smart-open-single-window-apps'
            always just switch.
            """,
        flags: [:],
        posArgs: [newMandatoryPosArgParser(\.appName, parseAppName, placeholder: "<app-name>")],
    )

    public var appName: Lateinit<String> = .uninitialized
}

func parseAppName(i: PosArgParserInput) -> ParsedCliArgs<String> {
    .succ(i.arg, advanceBy: 1)
}

public func parseSmartOpenCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SmartOpenCmdArgs> {
    parseSpecificCmdArgs(SmartOpenCmdArgs(rawArgs: args), args)
}
