public struct SmartOpenCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .smartOpen,
        help: """
            USAGE: smart-open [-h|--help] [--workspace <workspace>] [--minimized] <app-name>

            Open <app-name>, but be smart about an already-running app:
              - not running                       -> launch it
              - running and can make a new window -> open a new window on the current workspace
              - running and single-window         -> focus the existing window (switch workspace)

            "Can make a new window" is detected from the app's own menu bar: a ⌘N item whose
            title contains the localized word for "window" (taken from the app's Window menu).
            Apps whose ⌘N does something else — Spotify's New Playlist, VS Code's New Text
            File — fall back to switching. Apps listed in 'smart-open-single-window-apps'
            always just switch.

            OPTIONS:
              --workspace <workspace>  Put the window this command opens on <workspace> instead
                                       of the focused one, and leave the focused workspace as it
                                       is. Only affects a window this command opens: an app that
                                       can only switch to its existing window ignores it.
              --minimized              Minimize the window this command opens the moment it
                                       appears, so it never shows up on screen. <workspace> must
                                       be listed in 'floating-workspaces' — minimizing is banned
                                       on tiling workspaces. Ignored for the same apps as above.
            """,
        flags: [
            "--workspace": singleValueSubArgParser(\.targetWorkspace, "<workspace>", WorkspaceName.parse),
            "--minimized": trueBoolFlag(\.openMinimized),
        ],
        posArgs: [newMandatoryPosArgParser(\.appName, parseAppName, placeholder: "<app-name>")],
    )

    public var appName: Lateinit<String> = .uninitialized
    public var targetWorkspace: WorkspaceName? = nil
    public var openMinimized: Bool = false
}

func parseAppName(i: PosArgParserInput) -> ParsedCliArgs<String> {
    .succ(i.arg, advanceBy: 1)
}

public func parseSmartOpenCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SmartOpenCmdArgs> {
    parseSpecificCmdArgs(SmartOpenCmdArgs(rawArgs: args), args)
}
