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
        ]), ["3996": "e", "39260": "r", builtinMonitorKey: "c"])
    }

    func testTwoMonitorsWithThePanelOff() {
        assertEquals(monitorLetters([
            testMonitorInfo("39260", x: 0, y: 0),
            testMonitorInfo("3996", x: -2560, y: 0),
        ]), ["3996": "e", "39260": "r"])
    }

    func testALoneMonitorIsE() {
        assertEquals(monitorLetters([testMonitorInfo("3996", x: 0, y: 0)]), ["3996": "e"])
        assertEquals(monitorLetters([testMonitorInfo(builtinMonitorKey, x: 0, y: 0, width: 1512, height: 982)]), [builtinMonitorKey: "e"])
    }

    func testTheStandInDisplayHasNoLetter() {
        assertEquals(monitorLetters([testMonitorInfo(standInMonitorKey, x: 0, y: 0, width: 1920, height: 1080)]), [:])
    }

    func testThreeAndFourInARow() {
        let three = (0 ..< 3).map { testMonitorInfo("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(three), ["m0": "e", "m1": "r", "m2": "t"])
        let four = (0 ..< 4).map { testMonitorInfo("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(four), ["m0": "e", "m1": "r", "m2": "t", "m3": "y"])
    }

    func testTwoRowsOfFour() {
        let top = (0 ..< 4).map { testMonitorInfo("t\($0)", x: CGFloat($0) * 2560, y: -1440) }
        let bottom = (0 ..< 4).map { testMonitorInfo("b\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(top + bottom), [
            "t0": "e", "t1": "r", "t2": "t", "t3": "y",
            "b0": "x", "b1": "c", "b2": "v", "b3": "b",
        ])
    }

    func testOneTwoAndThreeInTheSecondRow() {
        let top = testMonitorInfo("top", x: 0, y: -1440)
        let bottom = (0 ..< 3).map { testMonitorInfo("b\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters([top] + bottom.prefix(1)), ["top": "e", "b0": "c"])
        assertEquals(monitorLetters([top] + bottom.prefix(2)), ["top": "e", "b0": "c", "b1": "v"])
        assertEquals(monitorLetters([top] + bottom), ["top": "e", "b0": "x", "b1": "c", "b2": "v"])
    }

    func testAThirdRowAndAFifthInARowGetNoLetter() {
        let rows = (0 ..< 3).map { testMonitorInfo("r\($0)", x: 0, y: CGFloat($0) * 1440) }
        assertEquals(monitorLetters(rows), ["r0": "e", "r1": "c"])
        let five = (0 ..< 5).map { testMonitorInfo("m\($0)", x: CGFloat($0) * 2560, y: 0) }
        assertEquals(monitorLetters(five), ["m0": "e", "m1": "r", "m2": "t", "m3": "y"])
    }

    func testLetterDescriptionFindsTheMonitor() {
        let left = testMonitorInfo("3996", x: -2560, y: 0)
        let right = testMonitorInfo("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        assertEquals(parseMonitorDescription("letter:R").getOrDie(), .letter("r"))
        assertEquals(MonitorDescription.letter("r").resolveMonitor(sortedMonitors: sortedMonitorInfos)?.key, "39260")
        assertEquals(MonitorDescription.letter("e").resolveMonitor(sortedMonitors: sortedMonitorInfos)?.key, "3996")
        assertNil(MonitorDescription.letter("t").resolveMonitor(sortedMonitors: sortedMonitorInfos))
    }

    func testLetterDescriptionRejectsMoreThanOneLetter() {
        assertNotNil(parseMonitorDescription("letter:er").failureOrNil)
        assertNotNil(parseMonitorDescription("letter:").failureOrNil)
    }

    func testFocusMonitorByLetter() async throws {
        let left = testMonitorInfo("3996", x: -2560, y: 0)
        let right = testMonitorInfo("39260", x: 0, y: 0)
        plugTestMonitors(left, right)
        assertTrue(left.activeWorkspace.focusWorkspace())

        try await parseCommand("focus-monitor letter:r").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(focus.workspace, right.activeWorkspace)
    }
}
