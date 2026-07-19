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

@MainActor final class MissionControlViewModel: ObservableObject {
    @Published var workspaces: [MiniWorkspace] = []
    @Published var selectedName: String? = nil
    @Published var appeared = false
}

@MainActor enum MissionControl {
    static let workspaceOrder = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static var panel: NSPanel? = nil
    private static var model: MissionControlViewModel? = nil
    private static var refreshTimer: Timer? = nil
    private static var didRequestScreenCapture = false
    // Fallback for windows whose live capture transiently fails (kept only while the overlay is open).
    private static var imageCache: [UInt32: CGImage] = [:]
    static var isShown: Bool { panel != nil }

    static func toggle() {
        isShown ? hide() : show()
    }

    static func hide(refocus: Bool = true) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let closing = panel, let closingModel = model, motionAllowed {
            withAnimation(.easeOut(duration: 0.15)) { closingModel.appeared = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { closing.orderOut(nil) }
        } else {
            panel?.orderOut(nil)
        }
        panel = nil
        model = nil
        imageCache = [:]
        resumeHotkeys()
        if refocus {
            Task {
                try await runLightSession(.menuBarButton, .checkServerIsEnabledOrDie()) {
                    _ = Workspace.get(byName: focus.workspace.name).focusWorkspace()
                }
            }
        }
    }

    static func show() {
        if isShown { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let viewModel = MissionControlViewModel()
        viewModel.workspaces = capture()
        viewModel.selectedName = focus.workspace.name
        model = viewModel
        // nonactivatingPanel: must display and take keyboard even when macOS
        // denies app activation (a freshly relaunched accessory app always is denied).
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
            model: viewModel,
            monitorAspect: mainMonitor.width / max(mainMonitor.height, 1),
        ))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        panel = p
        suspendHotkeys()
        if motionAllowed {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { viewModel.appeared = true }
            }
        } else {
            viewModel.appeared = true
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard isShown, let model else { return }
                // Watchdog: an overlay that failed to display must never strand
                // the user with suspended hotkeys.
                if panel?.isVisible != true {
                    hide(refocus: false)
                    return
                }
                model.workspaces = capture()
            }
        }
    }

    static func switchTo(_ name: String) {
        hide(refocus: false)
        Task {
            try await runLightSession(.menuBarButton, .checkServerIsEnabledOrDie()) {
                _ = Workspace.get(byName: name).focusWorkspace()
            }
        }
    }

    static func moveSelection(dx: Int, dy: Int) {
        guard let model else { return }
        let columns = 5
        let rows = 2
        let current = model.selectedName.flatMap { workspaceOrder.firstIndex(of: $0) } ?? 0
        let col = ((current % columns) + dx + columns) % columns
        let row = ((current / columns) + dy + rows) % rows
        model.selectedName = workspaceOrder[row * columns + col]
    }

    static func activateSelection() {
        guard let name = model?.selectedName else { return }
        switchTo(name)
    }

    static func select(_ name: String) {
        model?.selectedName = name
    }

    // While the overlay is up, every AeroSpace hotkey is unregistered so alt-w/alt-hjkl/alt-shift-*
    // can't destroy or rearrange windows behind it. Digits, arrows, enter, and esc are handled by
    // the panel itself; F3 keeps working because Karabiner runs the CLI, not a hotkey.
    private static func suspendHotkeys() {
        Task { await activateMode_nonCancellable(nil) }
    }

    private static func resumeHotkeys() {
        Task {
            let target = config.floatingWorkspaces.contains(focus.workspace.name) ? floatingModeId : mainModeId
            await activateMode_nonCancellable(config.modes[target] != nil ? target : mainModeId)
        }
    }

    private static func preflightCanCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if !didRequestScreenCapture {
            didRequestScreenCapture = true
            CGRequestScreenCaptureAccess()
        }
        return false
    }

    private static func capture() -> [MiniWorkspace] {
        let canCapture = preflightCanCapture()
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
                if canCapture, let image = captureWindowImage(window.windowId) {
                    imageCache[window.windowId] = image
                }
                return MiniWindow(
                    id: window.windowId,
                    rect: rect,
                    icon: (window as? MacWindow)?.macApp.nsApp.icon,
                    image: imageCache[window.windowId],
                )
            }
            return MiniWorkspace(name: name, isFocused: name == focusedName, windows: windows)
        }
    }

    private static func normalizedFloatingRect(_ window: Window, _ workspace: Workspace, _ monitorRect: Rect) -> CGRect {
        var rect: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? = nil
        if workspace.isVisible, let b = cgWindowTopLeftBounds(window.windowId) {
            rect = (x: b.minX, y: b.minY, w: b.width, h: b.height)
        } else if workspace.isVisible, let r = window.lastAppliedLayoutPhysicalRect {
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
        switch event.keyCode {
            case 53: // esc
                Task { @MainActor in MissionControl.hide() }
                return
            case 123: // left
                Task { @MainActor in MissionControl.moveSelection(dx: -1, dy: 0) }
                return
            case 124: // right
                Task { @MainActor in MissionControl.moveSelection(dx: 1, dy: 0) }
                return
            case 125: // down
                Task { @MainActor in MissionControl.moveSelection(dx: 0, dy: 1) }
                return
            case 126: // up
                Task { @MainActor in MissionControl.moveSelection(dx: 0, dy: -1) }
                return
            case 36, 76, 49: // return, keypad enter, space
                Task { @MainActor in MissionControl.activateSelection() }
                return
            default: break
        }
        if let chars = event.charactersIgnoringModifiers, chars.count == 1, chars.allSatisfy(\.isNumber) {
            Task { @MainActor in MissionControl.switchTo(chars) }
            return
        }
        super.keyDown(with: event)
    }
}

struct MissionControlView: View {
    @ObservedObject var model: MissionControlViewModel
    let monitorAspect: CGFloat

    var body: some View {
        ZStack {
            BlurView()
            Color.black.opacity(0.25)
            VStack(spacing: 28) {
                row(Array(model.workspaces.prefix(5)), startIndex: 0)
                row(Array(model.workspaces.suffix(5)), startIndex: 5)
            }
            .padding(48)
            .scaleEffect(model.appeared ? 1 : 0.98)
        }
        .opacity(model.appeared ? 1 : 0)
        .ignoresSafeArea()
    }

    private func row(_ items: [MiniWorkspace], startIndex: Int) -> some View {
        HStack(spacing: 28) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, workspace in
                MiniWorkspaceCell(
                    workspace: workspace,
                    monitorAspect: monitorAspect,
                    isSelected: workspace.name == model.selectedName,
                )
                .opacity(model.appeared ? 1 : 0)
                .offset(y: model.appeared ? 0 : 8)
                .animation(
                    .easeOut(duration: 0.25).delay(model.appeared ? Double(startIndex + offset) * 0.02 : 0),
                    value: model.appeared,
                )
            }
        }
    }
}

private struct BlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct MiniWorkspaceCell: View {
    let workspace: MiniWorkspace
    let monitorAspect: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(isSelected ? 0.14 : 0.08))
                    ZStack(alignment: .topLeading) {
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
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Color.white : workspace.isFocused ? Color.accentColor : Color.white.opacity(0.25),
                            lineWidth: isSelected || workspace.isFocused ? 3 : 1,
                        )
                }
            }
            .aspectRatio(monitorAspect, contentMode: .fit)
            .scaleEffect(isSelected ? 1.04 : 1)
            .shadow(color: isSelected ? .black.opacity(0.5) : .clear, radius: 12, y: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
            Text(workspace.name)
                .font(.system(size: 15, weight: workspace.isFocused || isSelected ? .bold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .white : workspace.isFocused ? .accentColor : .white.opacity(0.8))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { MissionControl.select(workspace.name) }
        }
        .onTapGesture { MissionControl.switchTo(workspace.name) }
    }
}

private struct MiniWindowView: View {
    let window: MiniWindow

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.15))
            if let image = window.image {
                Color.clear
                    .overlay(
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill),
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ultraThinMaterial))
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                    .padding(.bottom, 3)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}
