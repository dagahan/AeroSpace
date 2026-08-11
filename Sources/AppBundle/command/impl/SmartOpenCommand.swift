import AppKit
import Common

struct SmartOpenCommand: Command {
    let args: SmartOpenCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let appName = args.appName.val
        let workspaceName = args.targetWorkspace?.raw ?? focus.workspace.name
        if args.openMinimized && !config.floatingWorkspaces.contains(workspaceName) {
            return .fail(io.err("--minimized needs a workspace listed in 'floating-workspaces'. Minimizing is banned on tiling workspace '\(workspaceName)'"))
        }
        let placement: SmartOpenPlacement? = args.targetWorkspace != nil || args.openMinimized
            ? SmartOpenPlacement(appName: appName, workspaceName: workspaceName, minimized: args.openMinimized)
            : nil

        let trackedWindows = MacWindow.allWindows.filter {
            $0.app.name == appName && !($0.parent is MacosPopupWindowsContainer)
        }

        // Not running (or running windowless) -> launch it, macOS decides placement.
        guard let anchor = trackedWindows.first else {
            if let placement { SmartOpen.expect(placement) }
            launch(appName, inBackground: placement != nil)
            return .succ
        }

        let pid = anchor.app.pid
        let isSingleWindow = config.smartOpenSingleWindowApps.contains(appName)

        if !isSingleWindow {
            // A background app's menu bar isn't pressable, so it has to be activated
            // first — but activating raises its existing window, and the visible
            // workspace would follow it there and back. Suppressing the follow keeps
            // that entirely off screen: the app becomes frontmost, its old window stays
            // parked on its own workspace, and the new window is born here.
            let original = focus.workspace
            suppressWorkspaceFollowUntil = .now + 2
            defer { if placement == nil { suppressWorkspaceFollowUntil = .distantPast } }

            anchor.macAppUnsafe.nsApp.activate(options: .activateIgnoringOtherApps)
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let placement { SmartOpen.expect(placement) }
            if SmartOpen.openNewWindow(pid: pid) {
                _ = original.focusWorkspace()
                return .succ
            }
            SmartOpen.abandonPlacement()
        }

        // Single-window, or the app has no "New Window" action -> switch to the existing one.
        _ = anchor.nodeWorkspace?.focusWorkspace()
        anchor.nativeFocus()
        return .succ
    }

    private func launch(_ appName: String, inBackground: Bool) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = inBackground ? ["-g", "-a", appName] : ["-a", appName]
        try? proc.run()
    }
}

struct SmartOpenPlacement: Sendable {
    let appName: String
    let workspaceName: String
    let minimized: Bool
}

enum SmartOpen {
    private static let placementLifetime: TimeInterval = 10
    private static let focusSettleAfterPlacement: TimeInterval = 1

    @MainActor private static var expected: (placement: SmartOpenPlacement, deadline: Date)? = nil

    private static let minimizeOnCreationLock = NSLock()
    nonisolated(unsafe) private static var minimizeOnCreation: (appName: String, deadline: Date)? = nil

    @MainActor static func expect(_ placement: SmartOpenPlacement) {
        let deadline = Date.now + placementLifetime
        expected = (placement, deadline)
        suppressWorkspaceFollowUntil = deadline
        setMinimizeOnCreation(placement.minimized ? (placement.appName, deadline) : nil)
    }

    static func minimizeIfExpected(_ newWindow: AXUIElement) {
        minimizeOnCreationLock.lock()
        let awaited = minimizeOnCreation
        minimizeOnCreationLock.unlock()
        guard let awaited, .now < awaited.deadline else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(newWindow, &pid) == .success,
              NSRunningApplication(processIdentifier: pid)?.localizedName == awaited.appName else { return }
        AXUIElementSetAttributeValue(newWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    private static func setMinimizeOnCreation(_ awaited: (appName: String, deadline: Date)?) {
        minimizeOnCreationLock.lock()
        minimizeOnCreation = awaited
        minimizeOnCreationLock.unlock()
    }

    @MainActor static func expectedPlacement(forAppNamed appName: String?) -> SmartOpenPlacement? {
        guard let expected, expected.placement.appName == appName, .now < expected.deadline else { return nil }
        return expected.placement
    }

    @MainActor static func fulfillPlacement() {
        let fulfilled = expected?.placement
        expected = nil
        setMinimizeOnCreation(nil)
        suppressWorkspaceFollowUntil = .now + focusSettleAfterPlacement
        if let fulfilled, fulfilled.minimized || fulfilled.workspaceName != focus.workspace.name {
            focus.windowOrNil?.nativeFocus()
        }
    }

    @MainActor static func abandonPlacement() {
        guard expected != nil else { return }
        expected = nil
        setMinimizeOnCreation(nil)
        suppressWorkspaceFollowUntil = .distantPast
    }

    // Presses the app's own New Window menu item (⌘N) via Accessibility.
    // Returns false if no such enabled item exists (i.e. the app can't make a window).
    @MainActor static func openNewWindow(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRaw = menuBarRef, CFGetTypeID(menuBarRaw) == AXUIElementGetTypeID()
        else { return false }
        let menuBar = menuBarRaw as! AXUIElement
        // ⌘N alone doesn't mean "new window": Spotify binds it to New Playlist, VS Code
        // to New Text File. Pressing those spawns junk, so unless the item names itself
        // after a window we report "can't" and the caller switches to the existing one.
        guard let windowWord = windowMenuTitle(menuBar) else { return false }
        guard let item = findNewWindowItem(menuBar, windowWord: windowWord, depth: 0) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    // The standard Window menu, identified by its Minimize (⌘M) item, spells the
    // localized word for "window": Window, Окно, Fenster, Fenêtre, 窗口.
    private static func windowMenuTitle(_ menuBar: AXUIElement) -> String? {
        for item in children(of: menuBar) {
            guard let title = string(item, kAXTitleAttribute), !title.isEmpty else { continue }
            if containsCmdItem(item, char: "m", depth: 0) { return title }
        }
        return nil
    }

    private static func containsCmdItem(_ element: AXUIElement, char: String, depth: Int) -> Bool {
        if depth > 3 { return false }
        for child in children(of: element) {
            if isCmdItem(child, char: char) { return true }
            if containsCmdItem(child, char: char, depth: depth + 1) { return true }
        }
        return false
    }

    private static func findNewWindowItem(_ element: AXUIElement, windowWord: String, depth: Int) -> AXUIElement? {
        if depth > 3 { return nil }
        for child in children(of: element) {
            if isCmdItem(child, char: "n"),
               let title = string(child, kAXTitleAttribute),
               title.localizedCaseInsensitiveContains(windowWord) { return child }
            if let found = findNewWindowItem(child, windowWord: windowWord, depth: depth + 1) { return found }
        }
        return nil
    }

    // An enabled menu item bound to Command + <char>, with no Shift/Option/Control.
    private static func isCmdItem(_ item: AXUIElement, char: String) -> Bool {
        guard let cmdChar = string(item, kAXMenuItemCmdCharAttribute), cmdChar.lowercased() == char
        else { return false }
        var modRef: CFTypeRef?
        let mods = (AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modRef) == .success
            ? (modRef as? Int) : nil) ?? -1
        guard mods == 0 else { return false } // 0 == Command only
        var enabledRef: CFTypeRef?
        let enabled = (AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabledRef) == .success
            ? (enabledRef as? Bool) : nil) ?? true
        return enabled
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
