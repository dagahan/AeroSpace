@testable import AppBundle
import Common
import XCTest

private let unpluggedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let withinGrace = unpluggedAt.addingTimeInterval(2)
private let afterGrace = unpluggedAt.addingTimeInterval(3.1)

private let leftAsMain = testMonitorInfo("3996", x: 0, y: 0)
private let rightAsSecondary = testMonitorInfo("39260", x: 2560, y: 0)
private let builtinAlone = testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)
private let standInAlone = testMonitorInfo(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)

@MainActor
private func plug(_ monitors: MonitorInfoImpl..., at now: Date) {
    unitTestMonitors = monitors
    gcMonitors(now: now)
    Workspace.garbageCollectUnusedWorkspaces()
}

@MainActor
private func floatingWindows(_ workspaceName: String, ids: [UInt32]) -> [Window] {
    ids.map { TestWindow.new(id: $0, parent: Workspace.get(byName: workspaceName).floatingWindowsContainer) }
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
        assertTrue(Workspace.get(byName: "3").focusWorkspace())
    }

    func testACableReseatedWithinTheGraceMovesNothing() {
        _ = floatingWindows("3996-S", ids: [1, 2])

        plug(rightDeskMonitor, at: unpluggedAt)
        plug(leftDeskMonitor, rightDeskMonitor, at: withinGrace)
        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace)

        assertEquals(windowIds("3996-S"), [1, 2])
        assertEquals(leftDeskMonitor.activeWorkspace.name, "3996-S")
    }

    func testAMonitorGoneForGoodFloatsItsWindowsOnWhatTheMainMonitorShows() {
        let tiled = TestWindow.new(id: 10, parent: Workspace.get(byName: "3").rootTilingContainer)
        _ = floatingWindows("3996-S", ids: [1, 2])

        plug(rightDeskMonitor, at: unpluggedAt)
        assertEquals(windowIds("3996-S"), [1, 2])
        plug(rightDeskMonitor, at: afterGrace)

        assertEquals(Workspace.get(byName: "3").floatingWindows.map(\.windowId), [1, 2])
        assertEquals(Workspace.get(byName: "3").floatingWindows.map(\.homeWorkspaceName), ["3996-S", "3996-S"])
        assertEquals(Workspace.get(byName: "3").rootTilingContainer.children.count, 1)
        assertFalse(tiled.isFloating)
    }

    func testVisitorsGoHomeWhenTheMonitorReturns() {
        _ = TestWindow.new(id: 10, parent: Workspace.get(byName: "3").rootTilingContainer)
        _ = floatingWindows("3996-S", ids: [1, 2, 3])
        plug(rightDeskMonitor, at: unpluggedAt)
        plug(rightDeskMonitor, at: afterGrace)

        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(60))

        assertEquals(windowIds("3996-S"), [1, 2, 3])
        assertEquals(windowIds("3"), [10])
        assertNil(Window.get(byId: 1)?.homeWorkspaceName)
    }

    func testAVisitorMovedByHandStaysWhereItWasPut() async throws {
        _ = floatingWindows("3996-S", ids: [1, 2])
        plug(rightDeskMonitor, at: unpluggedAt)
        plug(rightDeskMonitor, at: afterGrace)

        assertTrue(Window.get(byId: 2).orDie().focusWindow())
        try await parseCommand("move-node-to-workspace 5").cmdOrDie.run(.defaultEnv, .emptyStdin)
        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(60))

        assertEquals(windowIds("5"), [2])
        assertEquals(windowIds("3996-S"), [1])
    }

    func testAMonitorThatBecomesMainFloatsItsWindowsOnTheVisibleWorkspaceAtOnce() {
        _ = floatingWindows("3996-S", ids: [1])

        plug(leftAsMain, rightAsSecondary, at: unpluggedAt)

        assertEquals(leftAsMain.activeWorkspace.name, "3")
        assertEquals(rightAsSecondary.activeWorkspace.name, "39260-S")
        assertEquals(Workspace.get(byName: "3").floatingWindows.map(\.windowId), [1])
        assertEquals(Window.get(byId: 1)?.homeWorkspaceName, "3996-S")
    }

    func testAMonitorThatStopsBeingMainTakesItsWindowsBack() {
        _ = floatingWindows("3996-S", ids: [1])
        plug(leftAsMain, rightAsSecondary, at: unpluggedAt)
        _ = floatingWindows("39260-S", ids: [2])

        plug(leftDeskMonitor, rightDeskMonitor, at: unpluggedAt.addingTimeInterval(1))

        assertEquals(windowIds("3996-S"), [1])
        assertEquals(rightDeskMonitor.activeWorkspace.name, "3")
        assertEquals(Workspace.get(byName: "3").floatingWindows.map(\.windowId), [2])
        assertEquals(Window.get(byId: 2)?.homeWorkspaceName, "39260-S")
    }

    func testUndockingToTheLaptopBringsEveryMonitorsWindowsAfterTheGrace() {
        _ = floatingWindows("3996-S", ids: [1])
        plug(builtinAlone, at: unpluggedAt)
        assertEquals(builtinAlone.activeWorkspace.name, "3")
        assertEquals(windowIds("3996-S"), [1])

        plug(builtinAlone, at: afterGrace)
        assertEquals(windowIds("3"), [1])
    }

    func testNothingIsEverMergedIntoTheStandIn() {
        _ = floatingWindows("3996-S", ids: [1])
        plug(standInAlone, at: unpluggedAt)
        plug(standInAlone, at: afterGrace)
        assertEquals(windowIds("3996-S"), [1])

        plug(builtinAlone, at: afterGrace.addingTimeInterval(1))
        assertEquals(windowIds("3"), [1])
    }

    func testAMonitorNeverSeenBeforeTakesNothing() {
        _ = TestWindow.new(id: 1, parent: Workspace.get(byName: "3").rootTilingContainer)
        let third = testMonitorInfo("777", x: 2560, y: 0)
        plug(leftDeskMonitor, rightDeskMonitor, third, at: unpluggedAt)
        plug(leftDeskMonitor, rightDeskMonitor, third, at: afterGrace)
        assertEquals(windowIds("3"), [1])
        assertTrue(third.activeWorkspace.isEffectivelyEmpty)
    }

    func testHomesSurviveARestartWhileTheMonitorIsAway() {
        _ = floatingWindows("3996-S", ids: [1, 2])
        plug(rightDeskMonitor, at: unpluggedAt)
        plug(rightDeskMonitor, at: afterGrace)

        forgetMonitorsForTests()
        plug(rightDeskMonitor, at: afterGrace.addingTimeInterval(10))
        assertEquals(Window.get(byId: 1)?.homeWorkspaceName, "3996-S")

        plug(leftDeskMonitor, rightDeskMonitor, at: afterGrace.addingTimeInterval(20))
        assertEquals(windowIds("3996-S"), [1, 2])
    }

    func testARestartAfterAnUnplugStillMovesTheWindowsOnceTheGraceEnds() {
        _ = floatingWindows("3996-S", ids: [1])
        forgetMonitorsForTests()
        plug(rightDeskMonitor, at: unpluggedAt)
        assertEquals(windowIds("3996-S"), [1])
        plug(rightDeskMonitor, at: afterGrace)
        assertEquals(rightDeskMonitor.activeWorkspace.floatingWindows.map(\.windowId), [1])
    }

    func testFocusFollowsTheFocusedWindowWhenItsMonitorGoesAway() {
        let window = floatingWindows("3996-S", ids: [1])[0]
        assertTrue(window.focusWindow())
        plug(rightDeskMonitor, at: unpluggedAt)
        plug(rightDeskMonitor, at: afterGrace)
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.name, "3")
    }

    func testHomeIsSavedAndOldStateFilesStillLoad() throws {
        let saved = SavedWindow(workspace: "3", isFloating: true, order: 0, home: "39260-S")
        let decoded = try JSONDecoder().decode(SavedWindow.self, from: JSONEncoder().encode(saved))
        assertEquals(decoded.home, "39260-S")
        let old = try JSONDecoder().decode(SavedWindow.self, from: Data(#"{"workspace":"3","isFloating":false,"order":0}"#.utf8))
        assertNil(old.home)
    }
}
