import Foundation

@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

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

@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        // Don't follow macOS auto-activation of another app right after the last
        // window on the focused workspace was closed. Stay on the empty workspace.
        let stayOnEmptiedWorkspace = focus.workspace.name == lastEmptiedFocusedWorkspaceName
            && lastEmptiedFocusedWorkspaceDate.distance(to: .now) < 1
            && nativeFocused?.nodeWorkspace != focus.workspace
        if !stayOnEmptiedWorkspace && .now >= suppressWorkspaceFollowUntil {
            _ = nativeFocused?.focusWindow()
        }
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}
