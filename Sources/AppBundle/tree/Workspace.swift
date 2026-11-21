import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]

@MainActor private var screenPointToPrevVisibleWorkspace: [CGPoint: String] = [:]
@MainActor private var monitorKeyToScreenPointAtLastArrangement: [String: CGPoint] = [:]
@MainActor private var monitorKeyToLastVisibleWorkspaceName: [String: String] = [:]
@MainActor private var lastSharedWorkspaceShownOnMain: String? = nil
@MainActor private var screenPointToVisibleWorkspace: [CGPoint: Workspace] = [:]
@MainActor private var visibleWorkspaceToScreenPoint: [Workspace: CGPoint] = [:]

// The returned workspace must be invisible and it must belong to the requested monitor
@MainActor func getStubWorkspace(for monitor: MonitorInfo) -> Workspace {
    getStubWorkspace(forPoint: monitor.rect.topLeftCorner)
}

@MainActor
private func getStubWorkspace(forPoint point: CGPoint) -> Workspace {
    if perMonitorWorkspacesAreOn, let monitor = monitorInfos.first(where: { $0.rect.topLeftCorner == point }) {
        return monitor.isMain ? getSharedStubWorkspace() : getStubWorkspace(ownedBy: monitor)
    }
    if let prev = screenPointToPrevVisibleWorkspace[point].map({ Workspace.get(byName: $0) }),
       !prev.isVisible && prev.workspaceMonitor.rect.topLeftCorner == point && prev.forceAssignedMonitor == nil
    {
        return prev
    }
    if let candidate = Workspace.all
        .first(where: { !$0.isVisible && $0.workspaceMonitor.rect.topLeftCorner == point })
    {
        return candidate
    }
    return (1 ... Int.max).lazy
        .map { Workspace.get(byName: String($0)) }
        .first { $0.isEffectivelyEmpty && !$0.isVisible && !config.persistentWorkspaces.contains($0.name) && $0.forceAssignedMonitor == nil }
        .orDie("Can't create empty workspace")
}

@MainActor
private func getSharedStubWorkspace() -> Workspace {
    Workspace.get(byName: lastSharedWorkspaceShownOnMain ?? config.persistentWorkspaces.first ?? "1")
}

@MainActor
private func getStubWorkspace(ownedBy monitor: MonitorInfo) -> Workspace {
    if let lastVisible = monitorKeyToLastVisibleWorkspaceName[monitor.key].map({ Workspace.get(byName: $0) }),
       !lastVisible.isVisible && lastVisible.ownerMonitorKey == monitor.key
    {
        return lastVisible
    }
    return monitor.ownWorkspaces.first { !$0.isVisible }.orDie("Every workspace of monitor \(monitor.key) is visible")
}

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil

    @MainActor
    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(config.persistentWorkspaces.contains(name))),
        ].map { "\($0.0): \(String(describing: $0.1).singleQuoted)" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func garbageCollectUnusedWorkspaces() {
        for name in config.persistentWorkspaces {
            _ = get(byName: name) // Make sure that all persistent workspaces are "cached"
        }
        let monitorKeysOwningWorkspaces = monitorKeysOwningWorkspaces()
        for monitor in monitorInfos where monitorKeysOwningWorkspaces.contains(monitor.key) {
            _ = monitor.ownWorkspaces
        }
        workspaceNameToWorkspace = workspaceNameToWorkspace.filter { (_, workspace: Workspace) in
            config.persistentWorkspaces.contains(workspace.name) ||
                workspace.ownerMonitorKey.map(monitorKeysOwningWorkspaces.contains) == true ||
                !workspace.isEffectivelyEmpty ||
                workspace.isVisible ||
                workspace.name == focus.workspace.name
        }
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    @MainActor
    var isVisible: Bool { visibleWorkspaceToScreenPoint.keys.contains(self) }
    @MainActor
    var workspaceMonitor: MonitorInfo {
        forceAssignedMonitor
            ?? visibleWorkspaceToScreenPoint[self]?.monitorApproximation
            ?? assignedMonitorPoint?.monitorApproximation
            ?? mainMonitorInfo
    }
}

extension MonitorInfo {
    @MainActor
    var activeWorkspace: Workspace {
        if let existing = screenPointToVisibleWorkspace[rect.topLeftCorner] {
            return existing
        }
        // What if monitor configuration changed? (frame.origin is changed)
        rearrangeWorkspacesOnMonitors()
        // Normally, recursion should happen only once more because we must take the value from the cache
        // (Unless, monitor configuration data race happens)
        return self.activeWorkspace
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func forgetMonitorsForTests() {
    screenPointToPrevVisibleWorkspace = [:]
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]
    monitorKeyToScreenPointAtLastArrangement = [:]
    monitorKeyToLastVisibleWorkspaceName = [:]
    lastSharedWorkspaceShownOnMain = nil
    forgetUnpluggedMonitorsForTests()
}

@MainActor
func gcMonitors(now: Date = .now) {
    let monitors = monitorInfos
    let someMonitorShowsAWorkspaceItMustNot = screenPointToVisibleWorkspace.contains { !isValidAssignment(workspace: $0.value, screen: $0.key) }
    if monitorKeyToScreenPoint(monitors) != monitorKeyToScreenPointAtLastArrangement ||
        screenPointToVisibleWorkspace.count != monitors.count ||
        someMonitorShowsAWorkspaceItMustNot
    {
        rearrangeWorkspacesOnMonitors()
    }
    if perMonitorWorkspacesAreOn {
        followUnpluggedAndReturningMonitors(monitors, now: now)
    }
    if !focus.workspace.isVisible {
        _ = focus.workspace.workspaceMonitor.setActiveWorkspace(focus.workspace)
    }
}

private func monitorKeyToScreenPoint(_ monitors: [MonitorInfo]) -> [String: CGPoint] {
    Dictionary(monitors.map { ($0.key, $0.rect.topLeftCorner) }, uniquingKeysWith: { first, _ in first })
}

extension CGPoint {
    @MainActor
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        if let prevMonitorPoint = visibleWorkspaceToScreenPoint[workspace] {
            visibleWorkspaceToScreenPoint.removeValue(forKey: workspace)
            screenPointToPrevVisibleWorkspace[prevMonitorPoint] =
                screenPointToVisibleWorkspace.removeValue(forKey: prevMonitorPoint)?.name
        }
        if let prevWorkspace = screenPointToVisibleWorkspace[self] {
            screenPointToPrevVisibleWorkspace[self] =
                screenPointToVisibleWorkspace.removeValue(forKey: self)?.name
            visibleWorkspaceToScreenPoint.removeValue(forKey: prevWorkspace)
        }
        visibleWorkspaceToScreenPoint[workspace] = self
        screenPointToVisibleWorkspace[self] = workspace
        workspace.assignedMonitorPoint = self
        return true
    }
}

@MainActor
private func rearrangeWorkspacesOnMonitors() {
    let newMonitors = monitorInfos
    let newScreens = newMonitors.map(\.rect.topLeftCorner)
    var newScreenToOldScreenMapping: [CGPoint: CGPoint] = [:]
    for monitor in newMonitors {
        if let oldScreen = monitorKeyToScreenPointAtLastArrangement[monitor.key], screenPointToVisibleWorkspace[oldScreen] != nil {
            newScreenToOldScreenMapping[monitor.rect.topLeftCorner] = oldScreen
        }
    }
    let oldScreensOfMonitorsStillPresent = newMonitors.compactMap { monitorKeyToScreenPointAtLastArrangement[$0.key] }.toSet()
    let screensMatchedByKey = newScreenToOldScreenMapping.keys.toSet()
    let newScreensToMatchByDistance = newScreens.filter { !screensMatchedByKey.contains($0) }
    for (oldScreen, _) in screenPointToVisibleWorkspace where !oldScreensOfMonitorsStillPresent.contains(oldScreen) {
        guard let newScreen = newScreensToMatchByDistance.minBy({ ($0 - oldScreen).vectorLength }) else { continue }
        if let prevOldScreen = newScreenToOldScreenMapping[newScreen] {
            if (prevOldScreen - newScreen).vectorLength <= (oldScreen - newScreen).vectorLength {
                // newScreen has already been assigned to a closer oldScreen.
                continue
            }
        }
        newScreenToOldScreenMapping[newScreen] = oldScreen
    }

    for (key, oldScreen) in monitorKeyToScreenPointAtLastArrangement {
        if let visible = screenPointToVisibleWorkspace[oldScreen] { monitorKeyToLastVisibleWorkspaceName[key] = visible.name }
    }
    if perMonitorWorkspacesAreOn, let shared = screenPointToVisibleWorkspace.values.first(where: { $0.ownerMonitorKey == nil }) {
        lastSharedWorkspaceShownOnMain = shared.name
    }
    let oldScreenPointToVisibleWorkspace = screenPointToVisibleWorkspace
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]

    for newScreen in newScreens {
        if let existingVisibleWorkspace = newScreenToOldScreenMapping[newScreen].flatMap({ oldScreenPointToVisibleWorkspace[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let stubWorkspace = getStubWorkspace(forPoint: newScreen)
        check(newScreen.setActiveWorkspace(stubWorkspace),
              "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace)) for the monitor (\(newScreen)")
    }
    monitorKeyToScreenPointAtLastArrangement = monitorKeyToScreenPoint(newMonitors)
}

@MainActor
private func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    if perMonitorWorkspacesAreOn {
        guard let monitor = monitorInfos.first(where: { $0.rect.topLeftCorner == screen }) else { return false }
        return workspace.ownerMonitorKey == (monitor.isMain ? nil : monitor.key)
    }
    return switch workspace.forceAssignedMonitor {
        case let forceAssigned? where forceAssigned.rect.topLeftCorner != screen: false
        default: true
    }
}
