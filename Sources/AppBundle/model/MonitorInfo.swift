import AppKit
import Common

struct MonitorInfoImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let key: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
}

extension MonitorInfoImpl: MonitorInfo {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol MonitorInfo: AeroAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var key: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}

final class LazyMonitorInfo: MonitorInfo {
    private let screen: NSScreen
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let key: String
    let width: CGFloat
    let height: CGFloat
    let isMain: Bool
    private var _rect: Rect?
    private var _visibleRect: Rect?

    init(monitorAppKitNsScreenScreensId: Int, key: String, isMain: Bool, _ screen: NSScreen) {
        self.monitorAppKitNsScreenScreensId = monitorAppKitNsScreenScreensId
        self.name = screen.localizedName
        self.key = key
        self.width = screen.frame.width // Don't call rect because it would cause recursion during mainMonitor init
        self.height = screen.frame.height // Don't call rect because it would cause recursion during mainMonitor init
        self.screen = screen
        self.isMain = isMain
    }

    var rect: Rect {
        _rect ?? screen.rect.also { _rect = $0 }
    }

    var visibleRect: Rect {
        _visibleRect ?? screen.visibleRect.also { _visibleRect = $0 }
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    fileprivate func toMonitorInfo(monitorAppKitNsScreenScreensId: Int, key: String) -> MonitorInfo {
        MonitorInfoImpl(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            key: key,
            rect: rect,
            visibleRect: visibleRect,
            isMain: isMainScreen,
        )
    }

    fileprivate var monitorKey: String {
        let displayId = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return monitorKeyOf(displayId: displayId)
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The property is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The property "normalizes" ``frame``
    fileprivate var rect: Rect { frame.monitorFrameNormalized() }

    /// Same as ``rect`` but for ``visibleFrame``
    fileprivate var visibleRect: Rect { visibleFrame.monitorFrameNormalized() }
}

let builtinMonitorKey = "builtin"
let standInMonitorKey = "stand-in"
private let standInVendorNumber: UInt32 = 0x756E_6B6E
private let standInModelNumber: UInt32 = 0x7669_7274

func monitorKeyOf(displayId: CGDirectDisplayID) -> String {
    if CGDisplayIsBuiltin(displayId) != 0 { return builtinMonitorKey }
    let serial = CGDisplaySerialNumber(displayId)
    if serial != 0 { return String(serial) }
    let vendor = CGDisplayVendorNumber(displayId)
    let model = CGDisplayModelNumber(displayId)
    if vendor == standInVendorNumber && model == standInModelNumber { return standInMonitorKey }
    return "\(vendor).\(model)"
}

extension MonitorInfo {
    var isStandIn: Bool { key == standInMonitorKey }
}

private let testMonitorInfoRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
let testMonitorInfo = MonitorInfoImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    key: "test",
    rect: testMonitorInfoRect,
    visibleRect: testMonitorInfoRect,
    isMain: true,
)
nonisolated(unsafe) var unitTestMonitors: [MonitorInfo] = [testMonitorInfo]

var mainMonitorInfo: MonitorInfo {
    if isUnitTest { return unsafe unitTestMonitors.first(where: \.isMain) ?? unitTestMonitors[0] }
    let screens = NSScreen.screens
    // Fallback: If main screen can't be found (e.g., during display reconfiguration),
    // return screens.first or testMonitor to avoid crash
    let screen = screens.withIndex.singleOrNil(where: \.value.isMainScreen) ?? screens.first.map { (0, $0) }
    guard let screen else { return testMonitorInfo }
    let key = uniqueMonitorKeys(screens)[screen.index]
    return LazyMonitorInfo(monitorAppKitNsScreenScreensId: screen.index + 1, key: key, isMain: true, screen.value)
}

var monitorInfos: [MonitorInfo] {
    if isUnitTest { return unsafe unitTestMonitors }
    let screens = NSScreen.screens
    return zip(screens.enumerated(), uniqueMonitorKeys(screens)).map { screen, key in
        screen.element.toMonitorInfo(monitorAppKitNsScreenScreensId: screen.offset + 1, key: key)
    }
}

private func uniqueMonitorKeys(_ screens: [NSScreen]) -> [String] {
    var timesSeen: [String: Int] = [:]
    return screens.map { screen in
        let key = screen.monitorKey
        let count = timesSeen[key, default: 0] + 1
        timesSeen[key] = count
        return count == 1 ? key : "\(key)#\(count)"
    }
}

var sortedMonitorInfos: [MonitorInfo] {
    monitorInfos.sortedBy([\.rect.minX, \.rect.minY])
}
