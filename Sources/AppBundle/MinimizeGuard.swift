import AppKit
import Common
import Foundation

nonisolated(unsafe) private var guardedRects: [CGRect] = []
private let rectsLock = NSLock()

private func storeGuardedRects(_ rects: [CGRect]) {
    rectsLock.lock()
    guardedRects = rects
    rectsLock.unlock()
}

private let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { MinimizeGuard.reenable() }
        }
        return Unmanaged.passUnretained(event)
    }
    let location = event.location
    rectsLock.lock()
    let hit = guardedRects.contains { $0.contains(location) }
    rectsLock.unlock()
    return hit ? nil : Unmanaged.passUnretained(event)
}

@MainActor enum MinimizeGuard {
    private static var tap: CFMachPort? = nil

    static func start() {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil,
        ) else { return }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
    }

    static func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    static func refresh() async {
        var rects: [CGRect] = []
        let workspace = focus.workspace
        if !config.floatingWorkspaces.contains(workspace.name) {
            for window in workspace.allLeafWindowsRecursive {
                guard let macWindow = window as? MacWindow else { continue }
                guard let rect = try? await macWindow.macApp.getMinimizeButtonRect(window.windowId, .nonCancellable) else { continue }
                rects.append(CGRect(x: rect.topLeftX, y: rect.topLeftY, width: rect.width, height: rect.height).insetBy(dx: -2, dy: -2))
            }
        }
        storeGuardedRects(rects)
    }
}
