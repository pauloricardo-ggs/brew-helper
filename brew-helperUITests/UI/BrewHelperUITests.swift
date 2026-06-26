import XCTest

final class BrewHelperUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFormulaeLoadOnLaunch() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["git"].exists)
        XCTAssertTrue(app.staticTexts["swiftlint"].exists)
        XCTAssertFalse(app.staticTexts["visual-studio-code"].exists)
    }

    func testServicesScreenShowsStatusAndControls() throws {
        let app = makeApp()
        app.launch()

        sidebarItem("sidebar.services", in: app).click()

        XCTAssertTrue(app.staticTexts["postgresql@16"].exists)
        XCTAssertTrue(app.staticTexts["Started"].exists)
        XCTAssertTrue(app.staticTexts["redis"].exists)
        XCTAssertTrue(app.staticTexts["Stopped"].exists)
        XCTAssertTrue(app.buttons["Stop"].exists)
        XCTAssertTrue(app.buttons["Start"].exists)
    }

    func testCasksAndTapsNavigationFiltersInstalledItems() throws {
        let app = makeApp()
        app.launch()

        sidebarItem("sidebar.casks", in: app).click()
        XCTAssertTrue(app.staticTexts["visual-studio-code"].exists)
        XCTAssertFalse(app.staticTexts["git"].exists)

        sidebarItem("sidebar.taps", in: app).click()
        XCTAssertTrue(app.staticTexts["homebrew/core"].exists)
        XCTAssertTrue(app.staticTexts["homebrew/cask"].exists)
        XCTAssertFalse(app.staticTexts["visual-studio-code"].exists)
    }

    func testSearchScreenReturnsInstallableResults() throws {
        let app = makeApp()
        app.launch()

        sidebarItem("sidebar.search", in: app).click()
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.exists)

        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        searchField.typeText("git")
        app.buttons["Search"].click()

        XCTAssertTrue(app.staticTexts["git-lfs"].exists)
        XCTAssertTrue(app.staticTexts["github"].exists)
        XCTAssertTrue(app.buttons["Install"].exists)
    }

    func testRemovingTapShowsConfirmationDialog() throws {
        let app = makeApp()
        app.launch()

        sidebarItem("sidebar.taps", in: app).click()
        XCTAssertTrue(app.staticTexts["homebrew/core"].exists)
        app.buttons["Remove"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Confirm Removal"].exists)
        XCTAssertTrue(app.buttons["Remove Tap"].exists)
        app.sheets.firstMatch.buttons["Cancel"].click()
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BREW_HELPER_UI_TESTING"] = "1"
        return app
    }

    private func sidebarItem(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}
