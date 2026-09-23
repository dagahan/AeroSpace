import Common

struct MoveNodeToWorkspaceCommand: Command {
    let args: MoveNodeToWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let subjectWs = window.nodeWorkspace
        let targetWorkspace: Workspace
        switch args.target.val {
            case .relative(let nextPrev):
                guard let subjectWs else { return .fail(io.err("Window \(window.windowId) doesn't belong to any workspace")) }
                let ws = getNextPrevWorkspace(
                    current: subjectWs,
                    isNext: nextPrev == .next,
                    wrapAround: args.wrapAround,
                    stdin: args.useStdin ? io.readStdin() : nil,
                    target: target,
                )
                guard let ws = ws.getOrNil(appendErrorTo: &io.stderr) else { return .fail }
                targetWorkspace = ws
            case .direct(let name):
                let monitor = pinnedMonitor ?? window.nodeMonitor ?? target.workspace.workspaceMonitor
                let workspaceName = resolveWorkspaceName(name.raw, on: monitor)
                if let problem = whyWorkspaceCantBeUsed(workspaceName) { return .fail(io.err(problem)) }
                targetWorkspace = Workspace.get(byName: workspaceName)
        }
        return moveWindowToWorkspace(window, targetWorkspace, io, focusFollowsWindow: args.focusFollowsWindow, failIfNoop: args.failIfNoop)
    }
}

@MainActor
func moveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, _ io: CmdIo, focusFollowsWindow: Bool, failIfNoop: Bool, index: Int = INDEX_BIND_LAST) -> BinaryExitCode {
    if window.nodeWorkspace == targetWorkspace {
        return switch failIfNoop {
            case true: .fail
            case false:
                .succ(io.err("Window '\(window.windowId)' already belongs to workspace '\(targetWorkspace.name)'. Tip: use --fail-if-noop to exit with non-zero code"))
        }
    }
    let sourceWorkspaceIsFloating = window.nodeWorkspace?.isFloatingWorkspace ?? false
    let targetWorkspaceIsFloating = targetWorkspace.isFloatingWorkspace
    let shouldFloat = targetWorkspaceIsFloating || (window.isFloating && !sourceWorkspaceIsFloating)
    let targetContainer: NonLeafTreeNodeObject = shouldFloat
        ? targetWorkspace.floatingWindowsContainer
        : targetWorkspace.rootTilingContainer
    window.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: index)
    window.homeWorkspaceName = nil
    return .from(bool: focusFollowsWindow ? window.focusWindow() : true)
}
