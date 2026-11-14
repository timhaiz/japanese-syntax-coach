import XCTest

final class AuthInteractionUITests: XCTestCase {
    func testLoginFormRemainsUsableWithKeyboardAndLocalConfigurationError() throws {
        try exerciseLoginForm()
    }

    func testLoginFormRemainsUsableWithLargestAccessibilityText() throws {
        try exerciseLoginForm(largeText: true)
    }

    private func exerciseLoginForm(largeText: Bool = false) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()

        let email = app.textFields["authEmailField"]
        let password = app.secureTextFields["authPasswordField"]
        let login = app.buttons["authPrimaryButton"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(login.exists)

        email.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "auth-keyboard-before-input"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        email.typeText("fixture@example.invalid")
        password.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        password.typeText("fictional-password-123")
        if !login.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(login.isHittable, "Login action should be reachable while the keyboard is visible")
        login.tap()

        let error = app.descendants(matching: .any)
            .matching(identifier: "authErrorMessage")
            .firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("配置") || String(describing: error.value).contains("配置"))
        let keyboardDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 5), .completed,
                       "Submitting should dismiss the keyboard without clearing the input")
        XCTAssertTrue(String(describing: email.value).contains("fixture@example.invalid"))
        XCTAssertNotEqual(String(describing: password.value), "密码")

        if !login.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        let reachable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: login
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed,
                       "Login action should remain available after an error and keyboard dismissal")
        login.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
    }
}
