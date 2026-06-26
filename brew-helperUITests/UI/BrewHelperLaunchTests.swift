import XCTest

final class BrewHelperLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BREW_HELPER_UI_TESTING"] = "1"
        app.launch()
    }
}
