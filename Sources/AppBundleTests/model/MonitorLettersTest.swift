@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorLettersTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTwoMonitorsAboveTheLaptop() {
        assertEquals(monitorLetters([
            testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982),
            testMonitorInfo("3996", x: -533, y: -1440),
            testMonitorInfo("39260", x: 2027, y: -1440),
        ]), ["3996": "d", "39260": "f", builtinMonitorKey: "c"])
    }

    func testTwoMonitorsWithThePanelOff() {
        assertEquals(monitorLetters([
            testMonitorInfo("39260", x: 0, y: 0),
            testMonitorInfo("3996", x: -2560, y: 0),
        ]), ["3996": "d", "39260": "f"])
    }

    func testALoneMonitorIsD() {
        assertEquals(monitorLetters([testMonitorInfo("3996", x: 0, y: 0)]), ["3996": "d"])
        assertEquals(monitorLetters([testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)]), [builtinMonitorKey: "d"])
    }

    func testTheStandInDisplayHasNoLetter() {
        assertEquals(monitorLetters([testMonitorInfo(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)]), [:])
    }

    func testThreeAndFourInARow() {
        let three = (0 ..< 3).map { testMonitorInfo("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(three), ["m0": "s", "m1": "d", "m2": "f"])
        let four = (0 ..< 4).map { testMonitorInfo("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(four), ["m0": "s", "m1": "d", "m2": "f", "m3": "g"])
    }

    func testLetterDescriptionFindsTheMonitor() {
        let left = testMonitorInfo("3996", x: -2560, y: 0)
        let right = testMonitorInfo("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        assertEquals(parseMonitorDescription("letter:F").getOrDie(), .letter("f"))
        assertEquals(MonitorDescription.letter("f").resolveMonitor(sortedMonitors: sortedMonitorInfos)?.key, "39260")
        assertEquals(MonitorDescription.letter("d").resolveMonitor(sortedMonitors: sortedMonitorInfos)?.key, "3996")
        assertNil(MonitorDescription.letter("s").resolveMonitor(sortedMonitors: sortedMonitorInfos))
    }

    func testLetterDescriptionRejectsMoreThanOneLetter() {
        assertNotNil(parseMonitorDescription("letter:df").failureOrNil)
        assertNotNil(parseMonitorDescription("letter:").failureOrNil)
    }

    func testFocusMonitorByLetter() async throws {
        let left = testMonitorInfo("3996", x: -2560, y: 0)
        let right = testMonitorInfo("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        assertTrue(left.activeWorkspace.focusWorkspace())

        try await parseCommand("focus-monitor letter:f").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(focus.workspace, right.activeWorkspace)
    }
}
