@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorIdentityTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEveryMonitorKeepsItsWorkspaceWhenThePanelReturnsAndOriginsShift() {
        plugTestMonitors(testMonitorInfo("39260", x: 0, y: 0), testMonitorInfo("3996", x: -2560, y: 0))
        let right = Workspace.get(byName: "right")
        let left = Workspace.get(byName: "left")
        assertTrue(testMonitorInfo("39260", x: 0, y: 0).setActiveWorkspace(right))
        assertTrue(testMonitorInfo("3996", x: -2560, y: 0).setActiveWorkspace(left))

        let builtin = testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)
        let leftAbove = testMonitorInfo("3996", x: -533, y: -1440)
        let rightAbove = testMonitorInfo("39260", x: 2027, y: -1440)
        plugTestMonitors(builtin, leftAbove, rightAbove)

        assertEquals(leftAbove.activeWorkspace, left)
        assertEquals(rightAbove.activeWorkspace, right)
        assertNotEquals(builtin.activeWorkspace, right)
        assertNotEquals(builtin.activeWorkspace, left)
    }

    func testTheSameMonitorsInTheSamePlacesChangeNothing() {
        let left = testMonitorInfo("3996", x: -2560, y: 0)
        let right = testMonitorInfo("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        let shownOnLeft = left.activeWorkspace
        let shownOnRight = right.activeWorkspace

        plugTestMonitors(right, left)

        assertEquals(left.activeWorkspace, shownOnLeft)
        assertEquals(right.activeWorkspace, shownOnRight)
    }

    func testMonitorKeyFormatVariable() {
        plugTestMonitors(testMonitorInfo("3996", x: 0, y: 0))
        assertEquals(FormatVar.monitor(.monitorKey).expandFormatVar(obj: .monitor(mainMonitorInfo)).getOrDie().toString(), "3996")
    }
}
