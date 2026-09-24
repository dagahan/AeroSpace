@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorTestDoubleTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTwoMonitorsEachShowAWorkspaceAndOneRemainsAfterUnplugging() {
        let left = testMonitorInfo("left", x: 0, y: 0)
        let right = testMonitorInfo("right", x: 2560, y: 0)
        plugTestMonitors(left, right)

        assertEquals(monitorInfos.map(\.key), ["left", "right"])
        assertNotEquals(left.activeWorkspace, right.activeWorkspace)
        assertEquals(mainMonitorInfo.key, "left")

        plugTestMonitors(left)

        assertEquals(monitorInfos.map(\.key), ["left"])
        assertTrue(left.activeWorkspace.isVisible)
    }
}
