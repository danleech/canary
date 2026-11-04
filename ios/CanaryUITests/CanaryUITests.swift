import StoreKitTest
import XCTest

/// End-to-end checks of what CI screenshots can't show: touches, pickers,
/// scrolling, sheets and purchases. Each test attaches screenshots to the result.
final class CanaryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ arguments: [String] = [], pins: String = "global-temp,earthquakes,oil") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CanaryPins", pins] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ app: XCUIApplication, labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// A tab's button. iPhone Duo's outer display draws the tab bar as a strip down
    /// the trailing edge, which XCTest doesn't report as a tab bar.
    @MainActor
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        return inBar.waitForExistence(timeout: 2) ? inBar : app.buttons[name].firstMatch
    }

    /// True on iPhone Duo's outer display, where the bar's buttons sit in the
    /// trailing strip and there is no title area at the top.
    @MainActor
    private func usesSideStrip(_ app: XCUIApplication) -> Bool {
        guard !app.tabBars.firstMatch.exists else { return false }
        let summary = app.buttons["Summary"].firstMatch
        return summary.exists && summary.frame.minX > app.frame.width * 0.75
    }

    /// The first launch fetches the board, so allow for the network.
    @MainActor
    private func waitForSummary(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 60), "Summary should load")
    }

    // MARK: Navigation

    @MainActor
    func testBrowseOpensDomain() {
        let app = launch()
        waitForSummary(app)
        snapshot("summary")
        tab(app, "Browse").tap()
        let tile = element(app, labelStartingWith: "Energy & Commodities")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        snapshot("browse")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Energy & Commodities"].waitForExistence(timeout: 10))
        snapshot("domain")
    }

    @MainActor
    func testSearchFindsSignal() {
        let app = launch()
        waitForSummary(app)
        tab(app, "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("sea ice")
        XCTAssertTrue(element(app, labelStartingWith: "Polar sea ice").waitForExistence(timeout: 10))
        snapshot("search")
    }

    // MARK: Signal detail

    @MainActor
    func testChartTouchSelectsACheck() {
        let app = launch(["-CanaryRoute", "canary://signal/earthquakes"])
        let chart = app.descendants(matching: .any)["valueChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 60), "value chart should appear")
        if !chart.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["LATEST"].exists)
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["SELECTED"].waitForExistence(timeout: 5), "touch should select a check")
        snapshot("chart-selected")
        app.buttons["Clear Selection"].tap()
        XCTAssertTrue(app.staticTexts["LATEST"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRangePickerChangesRange() {
        let app = launch(["-CanaryRoute", "canary://signal/earthquakes"])
        let day = app.buttons["D"]
        XCTAssertTrue(day.waitForExistence(timeout: 60))
        if !day.isHittable { app.swipeUp() }
        day.tap()
        XCTAssertTrue(day.isSelected)
        snapshot("range-day")
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["All"].isSelected)
    }

    @MainActor
    func testTitleAppearsAfterScrolling() throws {
        let app = launch(["-CanaryRoute", "canary://signal/earthquakes"])
        XCTAssertTrue(app.descendants(matching: .any)["valueChart"].firstMatch.waitForExistence(timeout: 60))
        if usesSideStrip(app) {
            throw XCTSkip("iPhone Duo's outer display has no title area in the navigation bar")
        }
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.navigationBars.staticTexts["Earthquakes & tsunami"].waitForExistence(timeout: 5),
                      "the name should move into the bar once the header scrolls away")
        snapshot("scrolled-title")
    }

    @MainActor
    func testPinFromDetailAddsTile() {
        let app = launch(["-CanaryRoute", "canary://signal/global-temp"], pins: "none")
        let pin = app.buttons["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 60))
        pin.tap()
        XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout: 5))
        // The back button is in the navigation bar, or in the trailing strip on iPhone Duo's outer display.
        let back = app.buttons["BackButton"].firstMatch
        (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
        XCTAssertTrue(element(app, labelStartingWith: "Global temperature").waitForExistence(timeout: 10))
        snapshot("pinned")
    }

    @MainActor
    func testWithheldSignalShowsLevelWithoutFigures() {
        let app = launch(["-CanaryRoute", "canary://signal/oil"])
        XCTAssertTrue(app.staticTexts["Figures Not Shown"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.descendants(matching: .any)["valueChart"].exists)
        snapshot("withheld")
    }

    // MARK: Sheets

    @MainActor
    func testSettingsOpensAndCloses() {
        let app = launch()
        waitForSummary(app)
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snapshot("settings")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testPaywallShowsSubscriptions() throws {
        let session = try SKTestSession(configurationFileNamed: "Canary")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let app = launch(["-CanarySheet", "plus"])
        let title = app.staticTexts["Canary+"]
        let unavailable = app.staticTexts["Subscription Unavailable"]
        let deadline = Date().addingTimeInterval(60)
        while !title.exists, !unavailable.exists, Date() < deadline { sleep(1) }
        sleep(3)
        snapshot("paywall")
        if unavailable.exists {
            throw XCTSkip("StoreKit test products didn't load in this environment")
        }
        XCTAssertTrue(title.exists, "paywall should show the Canary+ marketing header")
    }

    @MainActor
    func testWidgetGalleryRenders() {
        let app = launch(["-CanarySheet", "widgets"])
        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 60))
        sleep(2)
        snapshot("widgets-1")
        app.swipeUp()
        snapshot("widgets-2")
        app.swipeUp()
        snapshot("widgets-3")
    }
}
