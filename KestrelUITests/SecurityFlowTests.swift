import XCTest

/// Walks the security flows on a simulator with no wallet, in order: each test
/// leaves the wallet it made for the next one. PIN used throughout: 135790.
final class SecurityFlowTests: DrivenTestCase {
    let pin = "135790"

    func test1_NewWalletPINAndFaceID() {
        enrolFace(true)
        launch()
        waitFor(app.buttons["Create a new wallet"]).tap()
        waitFor(app.navigationBars["Recovery phrase"])
        shot("new-1-phrase")
        let toggle = waitFor(app.switches.firstMatch)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.buttons["Continue"].tap()

        waitFor(app.staticTexts["Create a PIN"])
        enterPIN(pin)
        waitFor(app.staticTexts["Confirm your PIN"])
        enterPIN(pin)

        let enable = app.alerts.buttons["Enable"]
        waitFor(enable, 20)
        shot("new-2-faceid-offer")
        enable.tap()
        matchFace()
        waitFor(app.buttons["Main wallet"], 20)
        shot("new-3-home")

        // Lock, then Face ID opens it.
        openSecuritySettings()
        XCTAssertEqual(app.switches["Face ID"].value as? String, "1", "Face ID should be on after accepting the offer")
        shot("new-4-security")
        app.buttons["Lock now"].tap()
        waitFor(app.staticTexts["Enter PIN"])
        XCTAssertTrue(app.buttons["Unlock with Face ID"].exists)
        app.buttons["Unlock with Face ID"].tap()
        matchFace()
        waitFor(app.buttons["Main wallet"], 20)

        // Lock again; the PIN opens it too, and a wrong one doesn't.
        openSecuritySettings()
        app.buttons["Lock now"].tap()
        waitFor(app.staticTexts["Enter PIN"])
        enterPIN("000000")
        waitFor(app.staticTexts["Wrong PIN"])
        XCTAssertFalse(isUnlocked)
        sleep(1)
        enterPIN(pin)
        waitFor(app.buttons["Main wallet"], 20)
    }
}
