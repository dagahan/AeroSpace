@testable import AppBundle
import Common
import XCTest

let leftDeskMonitor = testMonitor("3996", x: -2560, y: 0)
let rightDeskMonitor = testMonitor("39260", x: 0, y: 0)

@MainActor
func setUpPerMonitorWorkspaces() {
    config.perMonitorWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    config.floatingWorkspaces = ["1"]
    plugTestMonitors(leftDeskMonitor, rightDeskMonitor)
    Workspace.garbageCollectUnusedWorkspaces()
}

@MainActor
final class PerMonitorWorkspacesTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        setUpPerMonitorWorkspaces()
    }

    func testEveryMonitorStartsOnItsOwnFloatingOne() {
        assertEquals(leftDeskMonitor.activeWorkspace.name, "3996-1")
        assertEquals(rightDeskMonitor.activeWorkspace.name, "39260-1")
        assertTrue(leftDeskMonitor.activeWorkspace.isFloatingWorkspace)
        assertFalse(Workspace.get(byName: "3996-2").isFloatingWorkspace)
    }

    func testEveryConnectedMonitorKeepsItsTenWorkspaces() {
        let names = Workspace.all.map(\.name).toSet()
        for monitor in ["3996", "39260"] {
            for local in config.perMonitorWorkspaces {
                assertTrue(names.contains("\(monitor)-\(local)"))
            }
        }
    }

    func testWorkspaceNumberResolvesAgainstTheFocusedMonitor() async throws {
        assertTrue(rightDeskMonitor.activeWorkspace.focusWorkspace())
        try await parseCommand("workspace 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "39260-3")
        assertEquals(rightDeskMonitor.activeWorkspace.name, "39260-3")

        assertTrue(leftDeskMonitor.activeWorkspace.focusWorkspace())
        try await parseCommand("workspace 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "3996-3")
        assertEquals(rightDeskMonitor.activeWorkspace.name, "39260-3")
    }

    func testMoveNodeToWorkspaceNumberStaysOnTheWindowsMonitor() async throws {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: "3996-2").rootTilingContainer)
        assertTrue(window.focusWindow())
        try await parseCommand("move-node-to-workspace 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.nodeWorkspace?.name, "3996-3")
    }

    func testFullNamesStillWork() async throws {
        try await parseCommand("workspace 39260-5").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(rightDeskMonitor.activeWorkspace.name, "39260-5")
    }

    func testAWorkspaceIsNeverShownOnAnotherMonitor() {
        assertFalse(leftDeskMonitor.setActiveWorkspace(Workspace.get(byName: "39260-3")))
        assertEquals(Workspace.get(byName: "39260-3").forceAssignedMonitor?.key, "39260")
    }

    func testAMonitorComesBackShowingWhatItShowedBefore() {
        assertTrue(rightDeskMonitor.setActiveWorkspace(Workspace.get(byName: "39260-4")))
        plugTestMonitors(leftDeskMonitor)
        plugTestMonitors(leftDeskMonitor, rightDeskMonitor)
        assertEquals(rightDeskMonitor.activeWorkspace.name, "39260-4")
    }

    func testAMonitorNeverSeenBeforeShowsItsOwnOne() {
        let third = testMonitor("777", x: 2560, y: 0)
        plugTestMonitors(leftDeskMonitor, rightDeskMonitor, third)
        Workspace.garbageCollectUnusedWorkspaces()
        assertEquals(third.activeWorkspace.name, "777-1")
        assertTrue(third.ownWorkspaces.allSatisfy(\.isEffectivelyEmpty))
    }

    func testTheStandInGetsOneWorkspaceToShowAndKeepsNoneOfItsOwn() {
        let standIn = testMonitor(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)
        plugTestMonitors(standIn)
        Workspace.garbageCollectUnusedWorkspaces()
        assertEquals(standIn.activeWorkspace.name, "stand-in-1")
        assertFalse(Workspace.all.contains { $0.name == "stand-in-2" })
    }
}

@MainActor
final class PerMonitorWorkspaceRefusalTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        setUpPerMonitorWorkspaces()
    }

    func testAWorkspaceNoMonitorOwnsIsRefused() async throws {
        let result = try await parseCommand("workspace foo").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertNotEquals(result.exitCode.rawValue, 0)
        assertFalse(Workspace.all.contains { $0.name == "foo" && $0.isVisible })
    }

    func testAWorkspaceOfAnUnpluggedMonitorIsRefused() async throws {
        plugTestMonitors(leftDeskMonitor)
        let result = try await parseCommand("workspace 39260-3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertNotEquals(result.exitCode.rawValue, 0)
    }
}
