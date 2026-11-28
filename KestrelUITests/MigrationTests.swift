import XCTest

/// For a simulator that holds a wallet saved by a build from before the phrase was
/// sealed under the PIN. Pass the wallet's PIN as `TEST_RUNNER_WALLET_PIN`.
final class MigrationTests: DrivenTestCase {
    private var pin: String { ProcessInfo.processInfo.environment["WALLET_PIN"] ?? "" }

    func testExistingWalletUnlocksWithItsPINOnly() throws {
        try XCTSkipIf(pin.count != 6, "Set TEST_RUNNER_WALLET_PIN to the saved wallet's PIN")

        launch()
        waitFor(app.staticTexts["Enter PIN"])
        shot("migration-1-lock")
        enterPIN(pin)
        waitFor(app.tabBars.firstMatch, 30)
        shot("migration-2-unlocked")

        // The record written by that first entry must open again, and only with this PIN.
        launch()
        waitFor(app.staticTexts["Enter PIN"])
        enterPIN(pin == "111111" ? "333333" : "111111")
        waitFor(app.staticTexts["Wrong PIN"])
        shot("migration-3-wrong-pin")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        sleep(1)
        enterPIN(pin)
        waitFor(app.tabBars.firstMatch, 30)
        shot("migration-4-unlocked-again")
    }
}
