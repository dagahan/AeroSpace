@testable import AppBundle
import Common
import XCTest

private let unpluggedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let withinGrace = unpluggedAt.addingTimeInterval(2)
private let afterGrace = unpluggedAt.addingTimeInterval(3.1)

private let builtinUnderTheMonitors = testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)
private let leftAboveTheLaptop = testMonitorInfo("3996", x: -533, y: -1440)
private let rightAboveTheLaptop = testMonitorInfo("39260", x: 2027, y: -1440)
private let builtinAlone = testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)
private let standInAlone = testMonitorInfo(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)

@MainActor
private func plug(_ monitors: MonitorInfoImpl..., at now: Date) {
    unitTestMonitors = monitors
    gcMonitors(now: now)
    Workspace.garbageCollectUnusedWorkspaces()
}

@MainActor
private func tiledWindows(_ workspaceName: String, ids: [UInt32]) -> [Window] {
    ids.map { TestWindow.new(id: $0, parent: Workspace.get(byName: workspaceName).rootTilingContainer) }
}

@MainActor
private func windowIds(_ workspaceName: String) -> [UInt32] {
    Workspace.get(byName: workspaceName).allLeafWindowsRecursive.map(\.windowId)
}

@MainActor
final class UnpluggedMonitorsTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        setUpPerMonitorWorkspaces()
    }

    func testS1ACableReseatedWithinTheGraceMovesNothing() {
        _ = tiledWindows("39260-3", ids: [1, 2])
        assertTrue(rightDeskMonitor.setActiveWorkspace(Workspace.get(byName: "39260-3")))

        plug(leftDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, rightDeskMonitor, at: withinGrace)
        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace)

        assertEquals(windowIds("39260-3"), [1, 2])
        assertEquals(rightDeskMonitor.activeWorkspace.name, "39260-3")
    }

    func testS2AMonitorGoneForGoodJoinsTheNearestAsOneColumn() {
        let hosts = tiledWindows("3996-3", ids: [10, 11])
        hosts[0].setWeight(.h, 3)
        hosts[1].setWeight(.h, 1)
        _ = tiledWindows("39260-3", ids: [1, 2])

        plug(leftDeskMonitor, at: unpluggedAt)
        assertEquals(windowIds("39260-3"), [1, 2])
        plug(leftDeskMonitor, at: afterGrace)

        let root = Workspace.get(byName: "3996-3").rootTilingContainer
        assertEquals(root.children.count, 3)
        assertEquals(hosts[0].getWeight(.h), 3)
        assertEquals(hosts[1].getWeight(.h), 1)
        let column = root.children.last as? TilingContainer
        assertEquals(column?.layout, .accordion)
        assertEquals(column?.orientation, .v)
        assertEquals(column?.children.compactMap { ($0 as? Window)?.windowId }, [1, 2])
        assertEquals(column?.children.compactMap { ($0 as? Window)?.homeWorkspaceName }, ["39260-3", "39260-3"])
    }

    func testS3VisitorsGoHomeInTheirOrderWhenTheMonitorReturns() {
        _ = tiledWindows("3996-3", ids: [10, 11])
        _ = tiledWindows("39260-3", ids: [1, 2, 3])
        plug(leftDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, at: afterGrace)

        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(60))
        Workspace.get(byName: "3996-3").normalizeContainers()

        assertEquals(windowIds("39260-3"), [1, 2, 3])
        assertEquals(windowIds("3996-3"), [10, 11])
        assertEquals(Workspace.get(byName: "3996-3").rootTilingContainer.children.count, 2)
        assertNil(Window.get(byId: 1)?.homeWorkspaceName)
    }

    func testS4AVisitorMovedByHandStaysWhereItWasPut() async throws {
        _ = tiledWindows("39260-3", ids: [1, 2])
        plug(leftDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, at: afterGrace)

        assertTrue(Window.get(byId: 2).orDie().focusWindow())
        try await parseCommand("move-node-to-workspace 5").cmdOrDie.run(.defaultEnv, .emptyStdin)
        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(60))

        assertEquals(windowIds("3996-5"), [2])
        assertEquals(windowIds("39260-3"), [1])
    }

    func testS5FloatingWindowsStayFloatingBothWays() {
        let floating = TestWindow.new(id: 1, parent: Workspace.get(byName: "39260-1").floatingWindowsContainer)
        plug(leftDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, at: afterGrace)
        assertEquals(floating.nodeWorkspace?.name, "3996-1")
        assertTrue(floating.isFloating)

        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(60))
        assertEquals(floating.nodeWorkspace?.name, "39260-1")
        assertTrue(floating.isFloating)
    }

    func testS6UndockingBringsTheLaptopsWindowsHomeAtOnceAndTheMonitorsAfterTheGrace() {
        plug(builtinUnderTheMonitors, leftAboveTheLaptop, rightAboveTheLaptop, at: unpluggedAt.addingTimeInterval(-100))
        _ = tiledWindows("builtin-2", ids: [20])
        plug(leftAboveTheLaptop, rightAboveTheLaptop, at: unpluggedAt.addingTimeInterval(-50))
        plug(leftAboveTheLaptop, rightAboveTheLaptop, at: unpluggedAt.addingTimeInterval(-40))
        assertEquals(windowIds("3996-2"), [20])

        _ = tiledWindows("3996-4", ids: [1])
        _ = tiledWindows("39260-4", ids: [2])
        plug(builtinAlone, at: unpluggedAt)
        assertEquals(windowIds("builtin-2"), [20])
        assertEquals(windowIds("builtin-4"), [])

        plug(builtinAlone, at: afterGrace)
        assertEquals(windowIds("builtin-4").toSet(), [1, 2])
    }

    func testS7NothingIsEverMergedIntoTheStandIn() {
        _ = tiledWindows("3996-4", ids: [1])
        _ = tiledWindows("39260-4", ids: [2])
        plug(standInAlone, at: unpluggedAt)
        plug(standInAlone, at: afterGrace)
        assertEquals(windowIds("3996-4"), [1])
        assertEquals(windowIds("39260-4"), [2])
        assertFalse(Workspace.all.contains { $0.ownerMonitorKey == standInMonitorKey && !$0.isEffectivelyEmpty })

        plug(builtinAlone, at: afterGrace.addingTimeInterval(1))
        assertEquals(windowIds("builtin-4").toSet(), [1, 2])
    }

    func testS7WindowsBornOnTheStandInMoveToTheRealMonitorAtOnce() {
        plug(standInAlone, at: unpluggedAt)
        _ = tiledWindows("stand-in-1", ids: [7])
        plug(builtinAlone, at: unpluggedAt.addingTimeInterval(1.2))
        assertEquals(windowIds("builtin-1"), [7])
        assertNil(Window.get(byId: 7)?.homeWorkspaceName)
    }

    func testS8AMonitorNeverSeenBeforeTakesNothing() {
        _ = tiledWindows("3996-2", ids: [1])
        let third = testMonitorInfo("777", x: 2560, y: 0)
        plug(leftDeskMonitor, rightDeskMonitor, third, at: unpluggedAt)
        plug(leftDeskMonitor, rightDeskMonitor, third, at: afterGrace)
        assertEquals(windowIds("3996-2"), [1])
        assertTrue(third.ownWorkspaces.allSatisfy(\.isEffectivelyEmpty))
    }

    func testS9HomesSurviveARestartWhileTheMonitorIsAway() {
        _ = tiledWindows("39260-3", ids: [1, 2])
        plug(leftDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, at: afterGrace)

        forgetMonitorsForTests()
        plug(leftDeskMonitor, at: afterGrace.addingTimeInterval(10))
        assertEquals(windowIds("3996-3"), [1, 2])

        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(20))
        assertEquals(windowIds("39260-3"), [1, 2])
    }

    func testARestartAfterAnUnplugStillMovesTheWindowsOnceTheGraceEnds() {
        _ = tiledWindows("39260-3", ids: [1])
        forgetMonitorsForTests()
        plug(leftDeskMonitor, at: unpluggedAt)
        assertEquals(windowIds("39260-3"), [1])
        plug(leftDeskMonitor, at: afterGrace)
        assertEquals(windowIds("3996-3"), [1])
    }

    func testFocusFollowsTheFocusedWindowWhenItsMonitorGoesAway() {
        let window = tiledWindows("39260-5", ids: [1])[0]
        assertTrue(window.focusWindow())
        plug(leftDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, at: afterGrace)
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.name, "3996-5")
        assertEquals(leftDeskMonitor.activeWorkspace.name, "3996-5")
    }

    func testHomeIsSavedAndOldStateFilesStillLoad() throws {
        let saved = SavedWindow(workspace: "3996-3", isFloating: false, order: 0, home: "39260-3")
        let decoded = try JSONDecoder().decode(SavedWindow.self, from: JSONEncoder().encode(saved))
        assertEquals(decoded.home, "39260-3")
        let old = try JSONDecoder().decode(SavedWindow.self, from: Data(#"{"workspace":"3","isFloating":false,"order":0}"#.utf8))
        assertNil(old.home)
    }
}

@MainActor
final class TurningOnPerMonitorWorkspacesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEachOldWorkspaceMovesToTheMonitorItWasShownOn() {
        plugTestMonitors(leftDeskMonitor, rightDeskMonitor)
        _ = TestWindow.new(id: 1, parent: Workspace.get(byName: "3").rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: Workspace.get(byName: "4").rootTilingContainer)
        assertTrue(leftDeskMonitor.setActiveWorkspace(Workspace.get(byName: "3")))
        assertTrue(rightDeskMonitor.setActiveWorkspace(Workspace.get(byName: "4")))

        config.perMonitorWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        gcMonitors()

        assertEquals(Workspace.get(byName: "3996-3").allLeafWindowsRecursive.map(\.windowId), [1])
        assertEquals(Workspace.get(byName: "39260-4").allLeafWindowsRecursive.map(\.windowId), [2])
        assertEquals(leftDeskMonitor.activeWorkspace.ownerMonitorKey, "3996")
        assertEquals(rightDeskMonitor.activeWorkspace.ownerMonitorKey, "39260")
    }
}
