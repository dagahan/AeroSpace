import AppKit

@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil
@MainActor private var lastKnownFrontmostApp: NSRunningApplication? = nil
@MainActor private var macOsTookFocusAway = false

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor var lastEmptiedFocusedWorkspaceName: String? = nil
@MainActor var lastEmptiedFocusedWorkspaceDate: Date = .distantPast

/// While this is in the future, a native focus change does not drag the visible
/// workspace along with it. smart-open has to activate an app to reach its menu
/// bar, and activating raises that app's existing window wherever it lives —
/// without this the screen takes a visible round trip to that workspace and back.
/// A deadline rather than a flag, so a command that dies midway cannot leave
/// focus tracking switched off forever.
@MainActor var suppressWorkspaceFollowUntil: Date = .distantPast

@MainActor func updateFocusCache(_ nativeFocused: Window?) async throws {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    let previousWindowIsGone = if let id = lastKnownNativeFocusedWindowId, id != nativeFocused?.windowId {
        try await hasLeftTheScreen(id)
    } else {
        false
    }
    let previousFrontmostApp = lastKnownFrontmostApp
    lastKnownFrontmostApp = NSWorkspace.shared.frontmostApplication
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        if .now >= suppressWorkspaceFollowUntil, let nativeFocused {
            // Don't follow macOS auto-activation of another app right after the last
            // window on the focused workspace was closed. Stay on the empty workspace.
            let stayOnEmptiedWorkspace = focus.workspace.name == lastEmptiedFocusedWorkspaceName
                && lastEmptiedFocusedWorkspaceDate.distance(to: .now) < 1
            let macOsReplacedVanishedFocus = previousFrontmostApp?.hasExited == true
                || previousWindowIsGone
            macOsTookFocusAway = nativeFocused.nodeWorkspace != focus.workspace && (stayOnEmptiedWorkspace || macOsReplacedVanishedFocus)
            if !macOsTookFocusAway {
                _ = nativeFocused.focusWindow()
            }
        }
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}

@MainActor func takeFocusBackIfMacOsTookItAway() {
    guard macOsTookFocusAway else { return }
    macOsTookFocusAway = false
    if let window = focus.windowOrNil {
        window.nativeFocus()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor private func hasLeftTheScreen(_ windowId: UInt32) async throws -> Bool {
    guard let window = MacWindow.allWindowsMap[windowId] else { return true }
    if window.parent is MacosFullscreenWindowsContainer { return false }
    if try await window.isMacosMinimized(.cancellable) { return true }
    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(windowId)) as? [[String: Any]]
    return info?.first?[kCGWindowIsOnscreen as String] as? Bool != true
}

extension NSRunningApplication {
    fileprivate var hasExited: Bool { kill(processIdentifier, 0) == -1 && errno == ESRCH }
}
