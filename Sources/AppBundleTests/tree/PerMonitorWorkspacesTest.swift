@testable import AppBundle
import Common
import XCTest

let leftDeskMonitor = testMonitorInfo("3996", x: -2560, y: 0)
let rightDeskMonitor = testMonitorInfo("39260", x: 0, y: 0)

@MainActor
func setUpPerMonitorWorkspaces() {
    config.perMonitorWorkspaces = ["S"]
    config.floatingWorkspaces = ["1", "S"]
    plugTestMonitors(leftDeskMonitor, rightDeskMonitor)
    Workspace.garbageCollectUnusedWorkspaces()
}

@MainActor
final class PerMonitorWorkspacesTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        setUpPerMonitorWorkspaces()
    }

    func testTheMainMonitorShowsASharedWorkspaceAndASecondaryShowsItsOwn() {
        assertNil(rightDeskMonitor.activeWorkspace.ownerMonitorKey)
        assertEquals(leftDeskMonitor.activeWorkspace.name, "3996-S")
        assertTrue(leftDeskMonitor.activeWorkspace.isFloatingWorkspace)
        assertFalse(Workspace.all.contains { $0.name == "39260-S" })
    }

    func testAWorkspaceNumberOpensOnTheMainMonitorFromAnyMonitor() async throws {
        assertTrue(leftDeskMonitor.activeWorkspace.focusWorkspace())
        try await parseCommand("workspace 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "3")
        assertEquals(rightDeskMonitor.activeWorkspace.name, "3")
        assertEquals(leftDeskMonitor.activeWorkspace.name, "3996-S")
        assertTrue(Workspace.get(byName: "1").isFloatingWorkspace)
        assertFalse(Workspace.get(byName: "3").isFloatingWorkspace)
    }

    func testMoveNodeToWorkspaceNumberLeavesFocusWhereItIs() async throws {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: "3996-S").floatingWindowsContainer)
        assertTrue(window.focusWindow())
        try await parseCommand("move-node-to-workspace 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.nodeWorkspace?.name, "3")
        assertEquals(focus.workspace.name, "3996-S")
    }

    func testMoveNodeToMonitorByLetterLandsOnWhatThatMonitorShows() async throws {
        try await parseCommand("workspace 4").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: "4").rootTilingContainer)
        assertTrue(window.focusWindow())

        try await parseCommand("move-node-to-monitor --focus-follows-window letter:e").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.nodeWorkspace?.name, "3996-S")
        assertTrue(window.isFloating)
        assertEquals(focus.workspace.name, "3996-S")

        try await parseCommand("move-node-to-monitor --focus-follows-window letter:r").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.nodeWorkspace?.name, "4")
        assertEquals(focus.workspace.name, "4")
    }

    func testFocusMonitorByLetterReachesBothKinds() async throws {
        try await parseCommand("focus-monitor letter:e").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "3996-S")
        try await parseCommand("focus-monitor letter:r").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertNil(focus.workspace.ownerMonitorKey)
    }

    func testAWorkspaceIsNeverShownOnAMonitorOfTheOtherKind() {
        assertFalse(leftDeskMonitor.setActiveWorkspace(Workspace.get(byName: "3")))
        assertFalse(rightDeskMonitor.setActiveWorkspace(Workspace.get(byName: "3996-S")))
        assertEquals(Workspace.get(byName: "3").forceAssignedMonitor?.key, "39260")
        assertEquals(Workspace.get(byName: "3996-S").forceAssignedMonitor?.key, "3996")
    }

    func testAMonitorNeverSeenBeforeShowsItsOwnWorkspace() {
        let third = testMonitorInfo("777", x: 2560, y: 0)
        plugTestMonitors(leftDeskMonitor, rightDeskMonitor, third)
        Workspace.garbageCollectUnusedWorkspaces()
        assertEquals(third.activeWorkspace.name, "777-S")
        assertTrue(third.activeWorkspace.isEffectivelyEmpty)
    }

    func testTheStandInGetsNoLetterAndNoWorkspaceOfItsOwn() {
        let standIn = testMonitorInfo(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)
        plugTestMonitors(standIn)
        Workspace.garbageCollectUnusedWorkspaces()
        assertNil(standIn.letter)
        assertNil(standIn.activeWorkspace.ownerMonitorKey)
        assertEquals(monitorKeysOwningWorkspaces(), [])
        assertFalse(Workspace.all.contains { $0.ownerMonitorKey == standInMonitorKey })
    }

    func testTheOwnWorkspaceOfTheMainOrOfAnUnpluggedMonitorIsRefused() async throws {
        for name in ["39260-S", "777-S"] {
            let result = try await parseCommand("workspace \(name)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertNotEquals(result.exitCode.rawValue, 0)
        }
    }
}
