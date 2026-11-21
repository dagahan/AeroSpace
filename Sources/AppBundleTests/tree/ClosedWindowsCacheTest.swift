@testable import AppBundle
import Common
import XCTest

@MainActor
final class ClosedWindowsCacheTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testAWindowComingBackDoesNotBringBackTheWorkspaceShownWhenItWasCached() async throws {
        let shownWhenCached = Workspace.get(byName: "shownWhenCached")
        assertTrue(shownWhenCached.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: shownWhenCached.rootTilingContainer)
        cacheClosedWindowIfNeeded()
        window.unbindFromParent()
        assertTrue(Workspace.get(byName: "shownNow").focusWorkspace())

        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)

        assertTrue(restored)
        assertEquals(focus.workspace.name, "shownNow")
        assertEquals(mainMonitorInfo.activeWorkspace.name, "shownNow")
    }

    func testTheFocusedWorkspaceIsShownAgainAfterAMonitorLostIt() {
        assertTrue(Workspace.get(byName: "focused").focusWorkspace())
        assertTrue(mainMonitorInfo.setActiveWorkspace(Workspace.get(byName: "shownInstead")))

        gcMonitors()

        assertEquals(mainMonitorInfo.activeWorkspace.name, "focused")
    }
}
