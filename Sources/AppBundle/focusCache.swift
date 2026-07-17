@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor var lastEmptiedFocusedWorkspaceName: String? = nil
@MainActor var lastEmptiedFocusedWorkspaceDate: Date = .distantPast

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
        if !stayOnEmptiedWorkspace {
            _ = nativeFocused?.focusWindow()
        }
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}
