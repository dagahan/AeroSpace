import AppKit
import Common

@MainActor var motionAllowed: Bool {
    config.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

@MainActor var easeOutQuint: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }

enum WorkspaceTransition: String, Sendable {
    case off, fade, slide
}

@MainActor func cocoaFrame(_ rect: Rect) -> NSRect {
    NSRect(
        x: rect.topLeftX,
        y: mainMonitor.height - rect.topLeftY - rect.height,
        width: rect.width,
        height: rect.height,
    )
}

// Real on-screen bounds (top-left global coords) straight from the window server.
// Works for floating windows, which never get lastAppliedLayoutPhysicalRect.
func cgWindowTopLeftBounds(_ windowId: UInt32) -> CGRect? {
    guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(windowId)) as? [[String: Any]],
          let dict = info.first?[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: dict)
    else { return nil }
    return bounds
}

private func scaledFrame(_ frame: NSRect, _ factor: CGFloat) -> NSRect {
    frame.insetBy(dx: frame.width * (1 - factor) / 2, dy: frame.height * (1 - factor) / 2)
}

@MainActor func makeOverlayWindow(frame: NSRect, level: NSWindow.Level) -> NSWindow {
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.ignoresMouseEvents = true
    window.level = level
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    return window
}

@MainActor enum ProxyAnimator {
    static func popOut(image: CGImage, frame: Rect) {
        let window = makeOverlayWindow(frame: cocoaFrame(frame), level: .floating)
        let view = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resizeAspectFill
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFrontRegardless()
        let target = scaledFrame(window.frame, 0.87)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            window.animator().alphaValue = 0
            window.animator().setFrame(target, display: true)
        }, completionHandler: { Task { @MainActor in window.orderOut(nil) } })
    }
}

@MainActor enum WorkspaceCurtain {
    private static var active = false

    static func cover(towardHigherIndex: Bool?) {
        guard motionAllowed, config.workspaceTransition != .off, !isStartup, !active,
              CGPreflightScreenCaptureAccess(),
              let shot = CGDisplayCreateImage(CGMainDisplayID()),
              let screen = NSScreen.screens.first
        else { return }
        active = true
        let window = makeOverlayWindow(frame: screen.frame, level: .screenSaver)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = shot
        view.layer?.contentsGravity = .resizeAspectFill
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFrontRegardless()
        let slide = config.workspaceTransition == .slide
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = slide ? 0.25 : 0.18
            ctx.timingFunction = easeOutQuint
            if slide, let towardHigherIndex {
                var target = screen.frame
                target.origin.x += towardHigherIndex ? -screen.frame.width : screen.frame.width
                window.animator().setFrame(target, display: true)
            } else {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                active = false
            }
        })
    }

    static func direction(from: String, to: String) -> Bool? {
        guard let fromIndex = MissionControl.workspaceOrder.firstIndex(of: from),
              let toIndex = MissionControl.workspaceOrder.firstIndex(of: to),
              fromIndex != toIndex
        else { return nil }
        return toIndex > fromIndex
    }
}
