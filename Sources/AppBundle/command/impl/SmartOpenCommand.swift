import AppKit
import Common

struct SmartOpenCommand: Command {
    let args: SmartOpenCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let appName = args.appName.val

        let trackedWindows = MacWindow.allWindows.filter {
            $0.app.name == appName && !($0.parent is MacosPopupWindowsContainer)
        }

        // Not running (or running windowless) -> launch it, macOS decides placement.
        guard let anchor = trackedWindows.first else {
            launch(appName)
            return .succ
        }

        let pid = anchor.app.pid
        let isSingleWindow = config.smartOpenSingleWindowApps.contains(appName)

        // Multi-window: open a fresh window on the current workspace, without activating
        // the app first (activation would yank us to its existing window's space).
        if !isSingleWindow, SmartOpen.openNewWindow(pid: pid) {
            return .succ
        }

        // Single-window, or the app has no "New Window" action -> switch to the existing one.
        _ = anchor.nodeWorkspace?.focusWorkspace()
        anchor.nativeFocus()
        return .succ
    }

    private func launch(_ appName: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", appName]
        try? proc.run()
    }
}

enum SmartOpen {
    // Presses the app's own File -> New Window menu item (⌘N) via Accessibility.
    // Returns false if no such enabled item exists (i.e. the app can't make a window).
    @MainActor static func openNewWindow(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef, CFGetTypeID(menuBar) == AXUIElementGetTypeID()
        else { return false }
        guard let item = findNewWindowItem(menuBar as! AXUIElement, depth: 0) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func findNewWindowItem(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 3 { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return nil }
        for child in children {
            if isNewWindowItem(child) { return child }
            if let found = findNewWindowItem(child, depth: depth + 1) { return found }
        }
        return nil
    }

    // A menu item bound to ⌘N (Command only, no Shift/Option/Control) that is enabled.
    // This is the language-independent signature of "New Window" / "New" across native apps.
    private static func isNewWindowItem(_ item: AXUIElement) -> Bool {
        var cmdCharRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &cmdCharRef) == .success,
              let cmdChar = cmdCharRef as? String, cmdChar.lowercased() == "n"
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
}
