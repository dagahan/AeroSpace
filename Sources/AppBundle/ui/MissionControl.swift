import AppKit
import Common
import SwiftUI

struct MiniWindow: Identifiable {
    let id: UInt32
    let rect: CGRect
    let icon: NSImage?
    let image: CGImage?
}

struct MiniWorkspace: Identifiable {
    var id: String { name }
    let name: String
    let isFocused: Bool
    let windows: [MiniWindow]
}

@MainActor enum MissionControl {
    static let workspaceOrder = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static var panel: NSPanel? = nil
    static var isShown: Bool { panel != nil }

    static func toggle() {
        isShown ? hide() : show()
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    static func show() {
        if isShown { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let model = capture()
        let p = MissionControlPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: MissionControlView(
            workspaces: model,
            monitorAspect: mainMonitor.width / max(mainMonitor.height, 1),
        ))
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    static func switchTo(_ name: String) {
        hide()
        Task {
            try await runLightSession(.menuBarButton, .checkServerIsEnabledOrDie()) {
                _ = Workspace.get(byName: name).focusWorkspace()
            }
        }
    }

    private static func capture() -> [MiniWorkspace] {
        let canCapture = CGPreflightScreenCaptureAccess()
        if !canCapture {
            CGRequestScreenCaptureAccess()
        }
        let focusedName = focus.workspace.name
        return workspaceOrder.map { name in
            let workspace = Workspace.get(byName: name)
            let monitorRect = workspace.workspaceMonitor.rect
            var tiled: [(Window, CGRect)] = []
            layoutMini(workspace.rootTilingContainer, in: CGRect(x: 0, y: 0, width: 1, height: 1), out: &tiled)
            let floating: [(Window, CGRect)] = workspace.floatingWindowsContainer.children
                .compactMap { $0 as? Window }
                .map { window in (window, normalizedFloatingRect(window, workspace, monitorRect)) }
            let windows = (tiled + floating).map { window, rect in
                MiniWindow(
                    id: window.windowId,
                    rect: rect,
                    icon: (window as? MacWindow)?.macApp.nsApp.icon,
                    image: canCapture ? captureWindowImage(window.windowId) : nil,
                )
            }
            return MiniWorkspace(name: name, isFocused: name == focusedName, windows: windows)
        }
    }

    private static func normalizedFloatingRect(_ window: Window, _ workspace: Workspace, _ monitorRect: Rect) -> CGRect {
        var rect: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? = nil
        if workspace.isVisible, let r = window.lastAppliedLayoutPhysicalRect {
            rect = (x: r.topLeftX, y: r.topLeftY, w: r.width, h: r.height)
        } else if let saved = RestoreState.lookup(window.windowId)?.frame {
            rect = (x: CGFloat(saved.x), y: CGFloat(saved.y), w: CGFloat(saved.width), h: CGFloat(saved.height))
        }
        guard let rect, monitorRect.width > 0, monitorRect.height > 0 else {
            return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        }
        return CGRect(
            x: (rect.x - monitorRect.topLeftX) / monitorRect.width,
            y: (rect.y - monitorRect.topLeftY) / monitorRect.height,
            width: rect.w / monitorRect.width,
            height: rect.h / monitorRect.height,
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func layoutMini(_ node: TreeNode, in rect: CGRect, out: inout [(Window, CGRect)]) {
        if let window = node as? Window {
            out.append((window, rect))
            return
        }
        guard let container = node as? TilingContainer, !container.children.isEmpty else { return }
        let weights = container.children.map { CGFloat($0.getWeight(container.orientation)) }
        let total = weights.reduce(0, +)
        var offset: CGFloat = 0
        for (child, weight) in zip(container.children, weights) {
            let fraction = total > 0 ? weight / total : 1 / CGFloat(container.children.count)
            let childRect = container.orientation == .h
                ? CGRect(x: rect.minX + offset * rect.width, y: rect.minY, width: fraction * rect.width, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + offset * rect.height, width: rect.width, height: fraction * rect.height)
            layoutMini(child, in: childRect, out: &out)
            offset += fraction
        }
    }

    private static func captureWindowImage(_ windowId: UInt32) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .nominalResolution])
    }
}

private final class MissionControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let escKeyCode: UInt16 = 53
        if event.keyCode == escKeyCode {
            Task { @MainActor in MissionControl.hide() }
            return
        }
        if let chars = event.charactersIgnoringModifiers, chars.count == 1, chars.allSatisfy(\.isNumber) {
            Task { @MainActor in MissionControl.switchTo(chars) }
            return
        }
        super.keyDown(with: event)
    }
}

struct MissionControlView: View {
    let workspaces: [MiniWorkspace]
    let monitorAspect: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(spacing: 28) {
                row(Array(workspaces.prefix(5)))
                row(Array(workspaces.suffix(5)))
            }
            .padding(48)
        }
        .ignoresSafeArea()
    }

    private func row(_ items: [MiniWorkspace]) -> some View {
        HStack(spacing: 28) {
            ForEach(items) { workspace in
                MiniWorkspaceCell(workspace: workspace, monitorAspect: monitorAspect)
            }
        }
    }
}

private struct MiniWorkspaceCell: View {
    let workspace: MiniWorkspace
    let monitorAspect: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                    ForEach(workspace.windows) { window in
                        MiniWindowView(window: window)
                            .frame(
                                width: max(window.rect.width * geo.size.width - 2, 8),
                                height: max(window.rect.height * geo.size.height - 2, 8),
                            )
                            .offset(
                                x: window.rect.minX * geo.size.width + 1,
                                y: window.rect.minY * geo.size.height + 1,
                            )
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(workspace.isFocused ? Color.accentColor : Color.white.opacity(0.25), lineWidth: workspace.isFocused ? 3 : 1)
                }
            }
            .aspectRatio(monitorAspect, contentMode: .fit)
            Text(workspace.name)
                .font(.system(size: 15, weight: workspace.isFocused ? .bold : .regular, design: .rounded))
                .foregroundColor(workspace.isFocused ? .accentColor : .white.opacity(0.8))
        }
        .contentShape(Rectangle())
        .onTapGesture { MissionControl.switchTo(workspace.name) }
    }
}

private struct MiniWindowView: View {
    let window: MiniWindow

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.15))
            if let image = window.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}
