@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorLettersTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTwoMonitorsAboveTheLaptop() {
        assertEquals(monitorLetters([
            testMonitor(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982),
            testMonitor("3996", x: -533, y: -1440),
            testMonitor("39260", x: 2027, y: -1440),
        ]), ["3996": "d", "39260": "f", builtinMonitorKey: "c"])
    }

    func testTwoMonitorsWithThePanelOff() {
        assertEquals(monitorLetters([
            testMonitor("39260", x: 0, y: 0),
            testMonitor("3996", x: -2560, y: 0),
        ]), ["3996": "d", "39260": "f"])
    }

    func testALoneMonitorIsD() {
        assertEquals(monitorLetters([testMonitor("3996", x: 0, y: 0)]), ["3996": "d"])
        assertEquals(monitorLetters([testMonitor(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)]), [builtinMonitorKey: "d"])
    }

    func testTheStandInDisplayHasNoLetter() {
        assertEquals(monitorLetters([testMonitor(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)]), [:])
    }

    func testThreeAndFourInARow() {
        let three = (0 ..< 3).map { testMonitor("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(three), ["m0": "s", "m1": "d", "m2": "f"])
        let four = (0 ..< 4).map { testMonitor("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(four), ["m0": "s", "m1": "d", "m2": "f", "m3": "g"])
    }

    func testLetterDescriptionFindsTheMonitor() {
        let left = testMonitor("3996", x: -2560, y: 0)
        let right = testMonitor("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        assertEquals(parseMonitorDescription("letter:F").getOrDie(), .letter("f"))
        assertEquals(MonitorDescription.letter("f").resolveMonitor(sortedMonitors: sortedMonitors)?.key, "39260")
        assertEquals(MonitorDescription.letter("d").resolveMonitor(sortedMonitors: sortedMonitors)?.key, "3996")
        assertNil(MonitorDescription.letter("s").resolveMonitor(sortedMonitors: sortedMonitors))
    }

    func testLetterDescriptionRejectsMoreThanOneLetter() {
        assertNotNil(parseMonitorDescription("letter:df").failureOrNil)
        assertNotNil(parseMonitorDescription("letter:").failureOrNil)
    }

    func testFocusMonitorByLetter() async throws {
        let left = testMonitor("3996", x: -2560, y: 0)
        let right = testMonitor("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        assertTrue(left.activeWorkspace.focusWorkspace())

        try await parseCommand("focus-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(focus.workspace, right.activeWorkspace)
    }
}
