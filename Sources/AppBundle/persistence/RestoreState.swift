import AppKit
import Common
import Foundation

struct SavedFrame: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct SavedWindow: Codable {
    var workspace: String
    var isFloating: Bool
    var order: Int
    var weight: Double?
    var frame: SavedFrame?
    var minimized: Bool? = nil
}

struct SavedWorkspaceLayout: Codable {
    var orientation: String
    var layout: String
}

struct SavedState: Codable {
    var focusedWorkspace: String = ""
    var workspaces: [String: SavedWorkspaceLayout] = [:]
    var windows: [String: SavedWindow] = [:]
}

@MainActor enum RestoreState {
    private static let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AeroSpace/restore-state.json")
    private static var loaded: SavedState? =
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) }
    private static var saveScheduled = false

    static func lookup(_ windowId: UInt32) -> SavedWindow? { loaded?.windows[String(windowId)] }
    static var savedFocusedWorkspace: String? { loaded?.focusedWorkspace.takeIf { !$0.isEmpty } }

    static func scheduleSave() {
        if isStartup || saveScheduled { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                saveScheduled = false
                saveNow()
            }
        }
    }

    static func saveNow() {
        var state = SavedState()
        state.focusedWorkspace = focus.workspace.name
        for workspace in Workspace.all {
            let root = workspace.rootTilingContainer
            state.workspaces[workspace.name] = SavedWorkspaceLayout(
                orientation: root.orientation == .h ? "h" : "v",
                layout: root.layout.rawValue,
            )
        }
        for window in MacWindow.allWindows {
            let key = String(window.windowId)
            let isMinimized = window.parent is MacosMinimizedWindowsContainer
            let workspaceName: String?
            if let workspace = window.nodeWorkspace {
                workspaceName = workspace.name
                window.lastKnownWorkspaceName = workspace.name
            } else if isMinimized {
                workspaceName = window.lastKnownWorkspaceName ?? loaded?.windows[key]?.workspace
            } else {
                workspaceName = nil
            }
            guard let workspaceName else { continue }
            let weight: Double? = (window.parent as? TilingContainer).flatMap { parent in
                parent.layout == .tiles ? Double(window.getWeight(parent.orientation)) : nil
            }
            let isFloating = isMinimized ? (loaded?.windows[key]?.isFloating ?? false) : window.isFloating
            let frame: SavedFrame? = if isFloating, !isMinimized, window.nodeWorkspace?.isVisible == true,
                let bounds = cgWindowTopLeftBounds(window.windowId)
            {
                SavedFrame(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
            } else {
                loaded?.windows[key]?.frame
            }
            state.windows[key] = SavedWindow(
                workspace: workspaceName,
                isFloating: isFloating,
                order: window.ownIndex ?? 0,
                weight: weight,
                frame: frame,
                minimized: isMinimized,
            )
        }
        loaded = state
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func restoreLayoutAfterStartup() -> Bool {
        guard let state = loaded else { return false }
        var restoredAnything = false
        for window in MacWindow.allWindows {
            guard let saved = lookup(window.windowId), saved.isFloating, let frame = saved.frame else { continue }
            window.setAxFrame(CGPoint(x: frame.x, y: frame.y), CGSize(width: frame.width, height: frame.height))
            restoredAnything = true
        }
        for workspace in Workspace.all {
            guard let savedLayout = state.workspaces[workspace.name] else { continue }
            let root = workspace.rootTilingContainer
            let restoredWindows = root.children
                .compactMap { $0 as? Window }
                .compactMap { window in lookup(window.windowId).map { (window, $0) } }
            if restoredWindows.isEmpty { continue }
            restoredAnything = true
            root.changeOrientation(savedLayout.orientation == "v" ? .v : .h)
            root.layout = savedLayout.layout.parseLayout() ?? root.layout
            for (i, pair) in restoredWindows.sorted(by: { $0.1.order < $1.1.order }).enumerated() {
                pair.0.bind(to: root, adaptiveWeight: pair.1.weight.map { CGFloat($0) } ?? WEIGHT_AUTO, index: i)
            }
        }
        return restoredAnything
    }
}
