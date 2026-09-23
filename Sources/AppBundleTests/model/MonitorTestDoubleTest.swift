@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorTestDoubleTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTwoMonitorsEachShowAWorkspaceAndOneRemainsAfterUnplugging() {
        let left = testMonitor("left", x: 0, y: 0)
        let right = testMonitor("right", x: 2560, y: 0)
        plugTestMonitors(left, right)

        assertEquals(monitors.map(\.key), ["left", "right"])
        assertNotEquals(left.activeWorkspace, right.activeWorkspace)
        assertEquals(mainMonitor.key, "left")

        plugTestMonitors(left)

        assertEquals(monitors.map(\.key), ["left"])
        assertTrue(left.activeWorkspace.isVisible)
    }
}
