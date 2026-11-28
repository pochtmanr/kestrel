import XCTest
import notify

/// Shared helpers for tests that drive the real app on a simulator.
@MainActor
class DrivenTestCase: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func launch(_ arguments: [String] = []) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
    }

    /// Types a PIN on the app's own keypad (it isn't a system keyboard).
    func enterPIN(_ pin: String, in container: XCUIElement? = nil) {
        let scope = container ?? app
        for digit in pin {
            let key = scope.buttons[String(digit)].firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 10), "PIN key \(digit) is missing")
            key.tap()
        }
    }

    @discardableResult
    func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing: \(element)", file: file, line: line)
        return element
    }

    func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    /// Saves the whole screen (system UI included, so the app switcher shows) under
    /// `build/ui-shots/`, which the simulator can reach because it shares the Mac's disk.
    func shot(_ name: String) {
        let folder = Self.shotsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = XCUIScreen.main.screenshot().pngRepresentation
        try? image.write(to: folder.appendingPathComponent("\(name).png"))
    }

    nonisolated static var shotsFolder: URL {
        if let custom = ProcessInfo.processInfo.environment["SHOTS_DIR"] { return URL(fileURLWithPath: custom) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/ui-shots")
    }

    func openAppSwitcher() {
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.999))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
    }

    // MARK: Face ID in the simulator (the same switches as Simulator's Features > Face ID menu)

    func enrolFace(_ enrolled: Bool) {
        var token: Int32 = 0
        notify_register_check("com.apple.BiometricKit.enrollmentChanged", &token)
        notify_set_state(token, enrolled ? 1 : 0)
        notify_post("com.apple.BiometricKit.enrollmentChanged")
    }

    /// The first Face ID use shows iOS's own permission alert before the scan.
    func allowFaceIDIfAsked() {
        for title in ["Allow", "OK"] {
            let button = springboard.alerts.buttons[title]
            if button.waitForExistence(timeout: 3) { button.tap(); return }
        }
    }

    func matchFace() { allowFaceIDIfAsked(); sleep(2); notify_post("com.apple.BiometricKit_Sim.pearl.match") }
    func rejectFace() { sleep(2); notify_post("com.apple.BiometricKit_Sim.pearl.nomatch") }

    // MARK: Common paths

    func openSecuritySettings() {
        waitFor(app.buttons["Main wallet"]).tap()
        waitFor(app.buttons["Settings"]).tap()
        waitFor(app.buttons["Security"]).tap()
        waitFor(app.navigationBars["Security"])
    }

    var isUnlocked: Bool { app.buttons["Main wallet"].exists }
}
