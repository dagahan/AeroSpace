import AppKit
import Common

struct PerMonitorWorkspaceName: Equatable {
    let ownerMonitorKey: String
    let localName: String

    var fullName: String { "\(ownerMonitorKey)-\(localName)" }
}

@MainActor var perMonitorWorkspacesAreOn: Bool { !config.perMonitorWorkspaces.isEmpty }

@MainActor func parsePerMonitorWorkspaceName(_ name: String) -> PerMonitorWorkspaceName? {
    guard perMonitorWorkspacesAreOn, let dash = name.lastIndex(of: "-") else { return nil }
    let owner = String(name[..<dash])
    let localName = String(name[name.index(after: dash)...])
    return !owner.isEmpty && config.perMonitorWorkspaces.contains(localName)
        ? PerMonitorWorkspaceName(ownerMonitorKey: owner, localName: localName)
        : nil
}

@MainActor func resolveWorkspaceName(_ name: String, on monitor: MonitorInfo) -> String {
    perMonitorWorkspacesAreOn && config.perMonitorWorkspaces.contains(name)
        ? PerMonitorWorkspaceName(ownerMonitorKey: monitor.key, localName: name).fullName
        : name
}

@MainActor func isFloatingWorkspaceName(_ name: String) -> Bool {
    config.floatingWorkspaces.contains(parsePerMonitorWorkspaceName(name)?.localName ?? name)
}

extension Workspace {
    @MainActor var ownerMonitorKey: String? { parsePerMonitorWorkspaceName(name)?.ownerMonitorKey }
    @MainActor var localName: String { parsePerMonitorWorkspaceName(name)?.localName ?? name }
    @MainActor var isFloatingWorkspace: Bool { isFloatingWorkspaceName(name) }
}

extension MonitorInfo {
    @MainActor func ownWorkspace(_ localName: String) -> Workspace {
        Workspace.get(byName: PerMonitorWorkspaceName(ownerMonitorKey: key, localName: localName).fullName)
    }

    @MainActor var ownWorkspaces: [Workspace] { config.perMonitorWorkspaces.map(ownWorkspace) }
}

@MainActor func whyWorkspaceCantBeUsed(_ name: String) -> String? {
    guard let owner = parsePerMonitorWorkspaceName(name)?.ownerMonitorKey else { return nil }
    return monitorKeysOwningWorkspaces().contains(owner)
        ? nil
        : "Workspace '\(name)' belongs to monitor '\(owner)', which is not a connected secondary monitor"
}

@MainActor func monitorKeysOwningWorkspaces() -> Set<String> {
    perMonitorWorkspacesAreOn ? monitorInfos.filter { !$0.isStandIn && !$0.isMain }.map(\.key).toSet() : []
}
