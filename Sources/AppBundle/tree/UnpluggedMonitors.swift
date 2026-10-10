import AppKit
import Common

@MainActor private var monitorKeysOwningWorkspacesLastTime: Set<String> = []
@MainActor private var stoppedOwningWorkspacesAt: [String: Date] = [:]
@MainActor private var graceEndRefreshScheduledAt: Date? = nil

@MainActor
func forgetUnpluggedMonitorsForTests() {
    monitorKeysOwningWorkspacesLastTime = []
    stoppedOwningWorkspacesAt = [:]
    graceEndRefreshScheduledAt = nil
}

@MainActor
func followUnpluggedAndReturningMonitors(_ monitors: [MonitorInfo], now: Date) {
    let owningKeys = monitorKeysOwningWorkspaces()
    for key in monitorKeysOwningWorkspacesLastTime.subtracting(owningKeys) where stoppedOwningWorkspacesAt[key] == nil {
        stoppedOwningWorkspacesAt[key] = now
    }
    for key in owningKeys {
        stoppedOwningWorkspacesAt.removeValue(forKey: key)
        if !monitorKeysOwningWorkspacesLastTime.contains(key) {
            bringVisitorsHome(toMonitor: key)
        }
    }
    monitorKeysOwningWorkspacesLastTime = owningKeys
    moveWindowsOfMonitorsThatStoppedOwningWorkspaces(monitors, owningKeys, now: now)
}

@MainActor
private func moveWindowsOfMonitorsThatStoppedOwningWorkspaces(_ monitors: [MonitorInfo], _ owningKeys: Set<String>, now: Date) {
    guard let main = monitors.first(where: { $0.isMain && !$0.isStandIn }) else { return }
    let connectedKeys = monitors.map(\.key).toSet()
    let focusedWindow = focus.windowOrNil
    let focusedWindowWorkspace = focusedWindow?.nodeWorkspace
    let focusedWorkspace = focus.workspace
    var focusedWorkspaceWasLeft = false
    var earliestGraceEnd: Date? = nil
    for workspace in Workspace.all where !workspace.isEffectivelyEmpty || workspace == focusedWorkspace {
        guard let owner = workspace.ownerMonitorKey, !owningKeys.contains(owner) else { continue }
        let isUnplugged = !connectedKeys.contains(owner) && owner != standInMonitorKey
        if isUnplugged, stoppedOwningWorkspacesAt[owner] == nil { stoppedOwningWorkspacesAt[owner] = now }
        let graceEnd = isUnplugged
            ? stoppedOwningWorkspacesAt[owner].orDie().addingTimeInterval(TimeInterval(config.unpluggedMonitorGraceSeconds))
            : now
        if now < graceEnd {
            earliestGraceEnd = min(earliestGraceEnd ?? graceEnd, graceEnd)
            continue
        }
        let host = main.activeWorkspace
        for window in workspace.allLeafWindowsRecursive {
            window.bind(to: containerKeepingNativeState(of: window, in: host), adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            if window.homeWorkspaceName == nil, owner != standInMonitorKey { window.homeWorkspaceName = workspace.name }
        }
        if workspace == focusedWorkspace { focusedWorkspaceWasLeft = true }
    }
    if let earliestGraceEnd { scheduleRefresh(at: earliestGraceEnd, now: now) }
    if let focusedWindow, focusedWindow.nodeWorkspace != focusedWindowWorkspace {
        _ = focusedWindow.focusWindow()
    } else if focusedWorkspaceWasLeft {
        _ = main.activeWorkspace.focusWorkspace()
    }
}

@MainActor
private func containerKeepingNativeState(of window: Window, in workspace: Workspace) -> NonLeafTreeNodeObject {
    switch window.parent {
        case is MacosFullscreenWindowsContainer: workspace.macOsNativeFullscreenWindowsContainer
        case is MacosHiddenAppsWindowsContainer: workspace.macOsNativeHiddenAppsWindowsContainer
        default: workspace.floatingWindowsContainer
    }
}

@MainActor
private func bringVisitorsHome(toMonitor key: String) {
    for workspace in Workspace.all {
        for window in workspace.allLeafWindowsRecursive {
            guard let homeName = window.homeWorkspaceName, parsePerMonitorWorkspaceName(homeName)?.ownerMonitorKey == key else { continue }
            window.bind(to: containerKeepingNativeState(of: window, in: Workspace.get(byName: homeName)), adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            window.homeWorkspaceName = nil
        }
    }
}

@MainActor
private func scheduleRefresh(at graceEnd: Date, now: Date) {
    if isUnitTest { return }
    if let scheduled = graceEndRefreshScheduledAt, scheduled <= graceEnd, scheduled > now { return }
    graceEndRefreshScheduledAt = graceEnd
    DispatchQueue.main.asyncAfter(deadline: .now() + graceEnd.timeIntervalSince(now) + 0.05) {
        Task { @MainActor in
            graceEndRefreshScheduledAt = nil
            scheduleCancellableCompleteRefreshSession(.unpluggedMonitorGraceEnded)
        }
    }
}
