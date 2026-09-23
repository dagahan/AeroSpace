@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorPinTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        setUpPerMonitorWorkspaces()
    }

    func testDoubleTapPinsAndDoubleTapAgainUnpins() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        noteLetterTap(onMonitor: "39260", at: start)
        assertNil(pinnedMonitorKey)
        noteLetterTap(onMonitor: "39260", at: start.addingTimeInterval(0.2))
        assertEquals(pinnedMonitorKey, "39260")
        noteLetterTap(onMonitor: "39260", at: start.addingTimeInterval(1))
        noteLetterTap(onMonitor: "39260", at: start.addingTimeInterval(1.25))
        assertNil(pinnedMonitorKey)
    }

    func testSlowTapsAndTapsOnDifferentMonitorsDontPin() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        noteLetterTap(onMonitor: "39260", at: start)
        noteLetterTap(onMonitor: "39260", at: start.addingTimeInterval(0.4))
        noteLetterTap(onMonitor: "3996", at: start.addingTimeInterval(0.5))
        assertNil(pinnedMonitorKey)
    }

    func testDoubleTappingFocusMonitorByLetterPins() async throws {
        try await parseCommand("focus-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await parseCommand("focus-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(pinnedMonitorKey, "39260")
        try await parseCommand("pin-monitor off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertNil(pinnedMonitorKey)
    }

    func testWhilePinnedAWindowIsSentToThePinnedMonitorAndFocusStays() async throws {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: "3996-2").rootTilingContainer)
        assertTrue(window.focusWindow())
        try await parseCommand("pin-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)

        try await parseCommand("move-node-to-workspace 7").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(window.nodeWorkspace?.name, "39260-7")
        assertEquals(focus.workspace.name, "3996-2")
    }

    func testThePinIsDroppedWhenItsMonitorIsUnplugged() async throws {
        try await parseCommand("pin-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)
        plugTestMonitors(leftDeskMonitor)
        assertNil(pinnedMonitorKey)
    }

    func testMenuBarShowsLetterAndNumberPerMonitorWithFocusAndPinMarked() async throws {
        try await parseCommand("workspace 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertTrue(Workspace.get(byName: "3996-3").focusWorkspace())
        try await parseCommand("pin-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertTrue(rightDeskMonitor.setActiveWorkspace(Workspace.get(byName: "39260-1")))
        activeMode = floatingModeId
        updateTrayText()
        assertEquals(TrayMenuModel.shared.trayText, "*D3 F1📌")
        activeMode = mainModeId
    }
}
