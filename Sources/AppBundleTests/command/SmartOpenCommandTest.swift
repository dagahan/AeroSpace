@testable import AppBundle
import Common
import XCTest

@MainActor
final class SmartOpenCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc("smart-open Finder", SmartOpenCmdArgs(appName: "Finder"))
        testParseSingleCommandSucc(
            "smart-open --workspace 3 Finder",
            SmartOpenCmdArgs(appName: "Finder").copy(\.targetWorkspace, WorkspaceName.parse("3").getOrDie()),
        )
        testParseSingleCommandSucc(
            "smart-open --workspace 1 --minimized Finder",
            SmartOpenCmdArgs(appName: "Finder")
                .copy(\.targetWorkspace, WorkspaceName.parse("1").getOrDie())
                .copy(\.openMinimized, true),
        )
        testParseSingleCommandSucc(
            "smart-open --minimized Finder",
            SmartOpenCmdArgs(appName: "Finder").copy(\.openMinimized, true),
        )
    }

    func testParseFail() {
        assertEquals(parseCommand("smart-open").errorOrNil, "ERROR: Argument '<app-name>' is mandatory")
        assertEquals(parseCommand("smart-open Finder --workspace").errorOrNil, "ERROR: '--workspace' must be followed by '<workspace>'")
    }
}
