import XCTest

final class ImportPickerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("UI at test end: \(app.debugDescription)")
    }
    func testNativeFilesSelectionAndPatch() {
        let app = XCUIApplication()
        app.launchArguments = ["--picker-uitest"]
        app.launch()
        app.cells["chooseIPA"].tap()
        let file = app.collectionViews.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "PickerHarness.ipa", "PickerHarness")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 25), "Seeded IPA must appear in native Files picker")
        file.tap()
        let selected = app.staticTexts["statusMessage"]
        XCTAssertTrue(selected.waitForExistence(timeout: 20))
        let ready = NSPredicate(format: "label CONTAINS %@", "Ready to patch")
        expectation(for: ready, evaluatedWith: selected)
        waitForExpectations(timeout: 20)
        app.cells["patchSelected"].tap()
        let patched = NSPredicate(format: "label CONTAINS %@", "Patched IPA ready")
        expectation(for: patched, evaluatedWith: selected)
        waitForExpectations(timeout: 30)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native IPA selected and patched"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testCompatibilityPickerCancellation() {
        let app = XCUIApplication()
        app.launch()
        app.staticTexts["Try compatibility import"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        cancel.tap()
        let status = app.staticTexts["statusMessage"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Selection cancelled"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
    }
}

final class BridgePickerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("UI at test end: \(app.debugDescription)")
    }
    func testFilesImageCallbackAndDismissal() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["harnessImage"].tap()
        let files = app.buttons["Browse Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        files.tap()
        let file = app.collectionViews.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "PickerBridge.png", "PickerBridge")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 25), "Seeded image must appear in native Files picker")
        file.tap()
        let result = app.staticTexts["harnessResult"]
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "PASS image; presenter=yes; dismiss=yes; bytes="), evaluatedWith: result)
        waitForExpectations(timeout: 25)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Files media delivered to original delegate"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testFilesCancellationDismissesOriginalPicker() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["harnessImage"].tap()
        app.buttons["Browse Files"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        cancel.tap()
        expectation(for: NSPredicate(format: "label == %@", "PASS cancel; presenter=yes; dismiss=yes"), evaluatedWith: app.staticTexts["harnessResult"])
        waitForExpectations(timeout: 20)
    }
}
