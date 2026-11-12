import XCTest

/// End-to-end checks of the first-run path and the daily check-in.
/// The app drafts plans on device in these runs, so no credentials are needed.
final class SummaUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(app, id)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(id)", file: file, line: line)
        if !target.isHittable { app.swipeUp() }
        target.tap()
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let field = element(app, "onboarding.textField")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
    }

    private func next(_ app: XCUIApplication) { tap(app, "onboarding.continue") }

    /// Welcome → guided questions → the generating screen.
    private func answerGuidedQuestions(_ app: XCUIApplication) {
        tap(app, "welcome.continue")
        tap(app, "path.guided")
        type(app, "Alex"); next(app)
        tap(app, "option.I want more discipline"); next(app)
        tap(app, "option.Reading"); tap(app, "option.Reflection"); next(app)
        type(app, "Read four books"); next(app)
        tap(app, "option.Low energy"); next(app)
        next(app) // the illustrative arc
        tap(app, "option.10 minutes"); next(app)
        // Schedule every day so the check-in is due whatever day the test runs.
        tap(app, "weekday.7"); tap(app, "weekday.1"); next(app)
        tap(app, "option.Morning"); next(app)
        tap(app, "option.Tiny — almost too easy"); next(app)
        type(app, "I read every morning before work"); next(app)
        next(app) // optional final question; the button now reads "Build my plan"
    }

    private func startPlan(_ app: XCUIApplication) {
        answerGuidedQuestions(app)
        tap(app, "generating.viewPlan")
        tap(app, "review.begin")
        XCTAssertTrue(element(app, "checkin.Read daily").waitForExistence(timeout: 10))
    }

    func testFirstRunThroughFirstCheckInAndUndo() {
        let app = launch()
        startPlan(app)

        let checkIn = element(app, "checkin.Read daily")
        XCTAssertTrue(checkIn.label.contains("Mark Read daily complete"))
        checkIn.tap()
        XCTAssertTrue(element(app, "checkin.undo").waitForExistence(timeout: 5))
        XCTAssertTrue(checkIn.label.contains("completed today"))

        // The same check-in drives the streak and completion on Progress.
        tap(app, "habit.open.Read daily")
        let streak = element(app, "progress.currentStreak")
        XCTAssertTrue(streak.waitForExistence(timeout: 5))
        XCTAssertTrue(streak.label.contains("current streak: 1"), streak.label)
        XCTAssertTrue(app.staticTexts["1 of 1 scheduled days"].exists || element(app, "progress.completion").exists)

        // Undo from the daily screen.
        app.tabBars.buttons["Heatmaps"].tap()
        checkIn.tap()
        XCTAssertTrue(checkIn.label.contains("Mark Read daily complete"))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(element(app, "progress.currentStreak").label.contains("current streak: 0"))
    }

    func testGenerationFailureKeepsAnswersAndOffersAStarterPlan() {
        let app = launch(["-simulateGenerationFailure"])
        answerGuidedQuestions(app)
        XCTAssertTrue(element(app, "generating.retry").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Your answers are saved'")).firstMatch.exists)
        tap(app, "generating.retry") // the simulated failure happens once; retry succeeds
        tap(app, "generating.viewPlan")
        XCTAssertTrue(element(app, "review.begin").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Made for your life, Alex."].exists)
    }

    func testCheckInSurvivesRelaunch() {
        var app = launch(["-persist", "-resetState"])
        startPlan(app)
        element(app, "checkin.Read daily").tap()
        XCTAssertTrue(element(app, "checkin.undo").waitForExistence(timeout: 5))
        app.terminate()

        app = launch(["-persist"])
        let checkIn = element(app, "checkin.Read daily")
        XCTAssertTrue(checkIn.waitForExistence(timeout: 10))
        XCTAssertTrue(checkIn.label.contains("completed today"))
        // Undo, relaunch, and confirm the undo was saved too.
        checkIn.tap()
        app.terminate()
        app = launch(["-persist"])
        XCTAssertTrue(element(app, "checkin.Read daily").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "checkin.Read daily").label.contains("Mark Read daily complete"))
    }
}
