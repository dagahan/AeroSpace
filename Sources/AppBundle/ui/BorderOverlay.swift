import AppKit
import Common

@MainActor enum BorderOverlay {
    private static var window: NSWindow? = nil
    private static var currentWindowId: UInt32? = nil
    private static var seenWindowIds: Set<UInt32> = []

    static func sync() {
        guard config.animationsEnabled, config.focusedBorder, !MissionControl.isShown,
              let focused = focus.windowOrNil,
              !focused.isFullscreen,
              !(focused.parent is MacosFullscreenWindowsContainer),
              !(focused.parent is MacosMinimizedWindowsContainer),
              !(focused.parent is MacosHiddenAppsWindowsContainer),
              let rect = focused.lastAppliedLayoutPhysicalRect
        else {
            hide()
            return
        }

        let target = cocoaFrame(rect).insetBy(dx: -3, dy: -3)
        let overlay = window ?? create()
        let isNewWindow = !seenWindowIds.contains(focused.windowId)
        let focusChanged = currentWindowId != focused.windowId
        seenWindowIds.insert(focused.windowId)
        currentWindowId = focused.windowId

        if !motionAllowed {
            overlay.setFrame(target, display: true)
            overlay.alphaValue = 1
            overlay.orderFrontRegardless()
        } else if isNewWindow {
            overlay.setFrame(target.insetBy(dx: target.width * 0.065, dy: target.height * 0.065), display: true)
            overlay.alphaValue = 0
            overlay.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.41
                ctx.timingFunction = easeOutQuint
                overlay.animator().setFrame(target, display: true)
                overlay.animator().alphaValue = 1
            }
        } else if focusChanged || overlay.alphaValue < 1 {
            overlay.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = easeOutQuint
                overlay.animator().setFrame(target, display: true)
                overlay.animator().alphaValue = 1
            }
        } else if overlay.frame != target {
            overlay.setFrame(target, display: true)
            overlay.orderFrontRegardless()
        }
    }

    static func hide() {
        guard let overlay = window, overlay.alphaValue > 0 else { return }
        currentWindowId = nil
        if motionAllowed {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                overlay.animator().alphaValue = 0
            }
        } else {
            overlay.alphaValue = 0
        }
    }

    private static func create() -> NSWindow {
        let overlay = makeOverlayWindow(frame: .zero, level: .floating)
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.borderWidth = 2.5
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.layer?.cornerRadius = 11
        view.autoresizingMask = [.width, .height]
        overlay.contentView = view
        window = overlay
        return overlay
    }
}
