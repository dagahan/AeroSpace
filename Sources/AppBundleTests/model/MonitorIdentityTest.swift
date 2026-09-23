@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorIdentityTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEveryMonitorKeepsItsWorkspaceWhenThePanelReturnsAndOriginsShift() {
        plugTestMonitors(testMonitor("39260", x: 0, y: 0), testMonitor("3996", x: -2560, y: 0))
        let right = Workspace.get(byName: "right")
        let left = Workspace.get(byName: "left")
        assertTrue(testMonitor("39260", x: 0, y: 0).setActiveWorkspace(right))
        assertTrue(testMonitor("3996", x: -2560, y: 0).setActiveWorkspace(left))

        let builtin = testMonitor(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)
        let leftAbove = testMonitor("3996", x: -533, y: -1440)
        let rightAbove = testMonitor("39260", x: 2027, y: -1440)
        plugTestMonitors(builtin, leftAbove, rightAbove)

        assertEquals(leftAbove.activeWorkspace, left)
        assertEquals(rightAbove.activeWorkspace, right)
        assertNotEquals(builtin.activeWorkspace, right)
        assertNotEquals(builtin.activeWorkspace, left)
    }

    func testTheSameMonitorsInTheSamePlacesChangeNothing() {
        let left = testMonitor("3996", x: -2560, y: 0)
        let right = testMonitor("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        let shownOnLeft = left.activeWorkspace
        let shownOnRight = right.activeWorkspace

        plugTestMonitors(right, left)

        assertEquals(left.activeWorkspace, shownOnLeft)
        assertEquals(right.activeWorkspace, shownOnRight)
    }

    func testMonitorKeyFormatVariable() {
        plugTestMonitors(testMonitor("3996", x: 0, y: 0))
        assertEquals(FormatVar.monitor(.monitorKey).expandFormatVar(obj: .monitor(mainMonitor)).getOrDie().toString(), "3996")
    }
}
