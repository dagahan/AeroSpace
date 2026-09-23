import AppKit
import Common

private struct UnpluggedMonitor {
    let lastRect: Rect?
    let neighbourRectsWhenUnplugged: [String: Rect]
    let unpluggedAt: Date
}

@MainActor private var realMonitorRectsSeenLastTime: [String: Rect] = [:]
@MainActor private var unpluggedMonitors: [String: UnpluggedMonitor] = [:]
@MainActor private var graceEndRefreshScheduledAt: Date? = nil

@MainActor
func forgetUnpluggedMonitorsForTests() {
    realMonitorRectsSeenLastTime = [:]
    unpluggedMonitors = [:]
    graceEndRefreshScheduledAt = nil
}

@MainActor
func followUnpluggedAndReturningMonitors(_ monitors: [Monitor], now: Date) {
    let realMonitors = monitors.filter { !$0.isStandIn }
    let realMonitorRects = Dictionary(realMonitors.map { ($0.key, $0.rect) }, uniquingKeysWith: { first, _ in first })
    for (key, rect) in realMonitorRectsSeenLastTime where realMonitorRects[key] == nil && unpluggedMonitors[key] == nil {
        unpluggedMonitors[key] = UnpluggedMonitor(lastRect: rect, neighbourRectsWhenUnplugged: realMonitorRectsSeenLastTime, unpluggedAt: now)
    }
    for key in realMonitorRects.keys {
        unpluggedMonitors.removeValue(forKey: key)
        if realMonitorRectsSeenLastTime[key] == nil {
            bringVisitorsHome(toMonitor: key)
        }
    }
    realMonitorRectsSeenLastTime = realMonitorRects
    moveWindowsOffMonitorsGoneForGood(realMonitors, now: now)
}

@MainActor
private func moveWindowsOffMonitorsGoneForGood(_ realMonitors: [Monitor], now: Date) {
    if realMonitors.isEmpty { return }
    let presentKeys = realMonitors.map(\.key).toSet()
    let focusedWindow = focus.windowOrNil
    let focusedWindowWorkspace = focusedWindow?.nodeWorkspace
    let focusedWorkspace = focus.workspace
    var hostOfFocusedWorkspace: Workspace? = nil
    var earliestGraceEnd: Date? = nil
    for workspace in Workspace.all where !workspace.isEffectivelyEmpty || workspace == focusedWorkspace {
        let owner = workspace.ownerMonitorKey
        if let owner, presentKeys.contains(owner) { continue }
        if let owner, owner != standInMonitorKey, unpluggedMonitors[owner] == nil {
            unpluggedMonitors[owner] = UnpluggedMonitor(lastRect: nil, neighbourRectsWhenUnplugged: [:], unpluggedAt: now)
        }
        let unplugged = owner.flatMap { unpluggedMonitors[$0] }
        let graceEnd = unplugged.map { $0.unpluggedAt.addingTimeInterval(TimeInterval(config.unpluggedMonitorGraceSeconds)) } ?? now
        if now < graceEnd {
            earliestGraceEnd = min(earliestGraceEnd ?? graceEnd, graceEnd)
            continue
        }
        let monitorItWasShownOn = owner == nil ? realMonitors.first { $0.key == workspace.workspaceMonitor.key } : nil
        let hostMonitor = monitorItWasShownOn ?? nearestMonitor(to: unplugged, among: realMonitors)
        let hostLocalName = config.perMonitorWorkspaces.contains(workspace.localName) ? workspace.localName : config.perMonitorWorkspaces.first.orDie()
        let host = hostMonitor.ownWorkspace(hostLocalName)
        let home = unplugged == nil ? nil : workspace.name
        moveWindows(of: workspace, into: host, rememberingHome: home)
        if workspace == focusedWorkspace { hostOfFocusedWorkspace = host }
    }
    if let earliestGraceEnd { scheduleRefresh(at: earliestGraceEnd, now: now) }
    if let focusedWindow, focusedWindow.nodeWorkspace != focusedWindowWorkspace {
        _ = focusedWindow.focusWindow()
    } else if let hostOfFocusedWorkspace {
        _ = hostOfFocusedWorkspace.workspaceMonitor.activeWorkspace.focusWorkspace()
    }
}

@MainActor
private func nearestMonitor(to unplugged: UnpluggedMonitor?, among monitors: [Monitor]) -> Monitor {
    guard let unplugged, let lastRect = unplugged.lastRect else {
        return monitors.first(where: \.isMain) ?? monitors.first.orDie()
    }
    return monitors.minByOrDie { monitor in
        let rectInTheSameArrangement = unplugged.neighbourRectsWhenUnplugged[monitor.key] ?? monitor.rect
        return (rectInTheSameArrangement.center - lastRect.center).vectorLength
    }
}

@MainActor
private func moveWindows(of lost: Workspace, into host: Workspace, rememberingHome home: String?) {
    var visitorsColumn: TilingContainer? = nil
    for window in lost.allLeafWindowsRecursive {
        let destination: NonLeafTreeNodeObject = switch window.parent {
            case is MacosFullscreenWindowsContainer: host.macOsNativeFullscreenWindowsContainer
            case is MacosHiddenAppsWindowsContainer: host.macOsNativeHiddenAppsWindowsContainer
            case is FloatingWindowsContainer: host.floatingWindowsContainer
            case _ where host.isFloatingWorkspace: host.floatingWindowsContainer
            default: visitorsColumn ?? makeVisitorsColumn(in: host).also { visitorsColumn = $0 }
        }
        window.bind(to: destination, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        if window.homeWorkspaceName == nil { window.homeWorkspaceName = home }
    }
}

@MainActor
private func makeVisitorsColumn(in host: Workspace) -> TilingContainer {
    let root = host.rootTilingContainer
    if root.children.isEmpty { return root }
    return TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, root.orientation.opposite, .accordion, index: INDEX_BIND_LAST)
}

@MainActor
private func bringVisitorsHome(toMonitor key: String) {
    for workspace in Workspace.all {
        for window in workspace.allLeafWindowsRecursive {
            guard let homeName = window.homeWorkspaceName, parsePerMonitorWorkspaceName(homeName)?.ownerMonitorKey == key else { continue }
            let home = Workspace.get(byName: homeName)
            let destination: NonLeafTreeNodeObject = switch window.parent {
                case is MacosFullscreenWindowsContainer: home.macOsNativeFullscreenWindowsContainer
                case is MacosHiddenAppsWindowsContainer: home.macOsNativeHiddenAppsWindowsContainer
                case is FloatingWindowsContainer: home.floatingWindowsContainer
                case _ where home.isFloatingWorkspace: home.floatingWindowsContainer
                default: home.rootTilingContainer
            }
            window.bind(to: destination, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
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
