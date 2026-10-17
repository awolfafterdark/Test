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
        let displayName = app.navigationBars.firstMatch.identifier
        app.cells["chooseIPA"].tap()
        selectNativeFile(app, name: "PickerHarness.ipa", folders: [displayName, "Imports"])
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
        let cancel = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Cancel"]
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
        app.launchArguments = ["--double-hook"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Injected framework 0.7.0"].waitForExistence(timeout: 10))
        app.buttons["harnessImage"].tap()
        let files = app.buttons["Browse Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        files.tap()
        selectNativeFile(app, name: "PickerBridge.png", folders: ["Picker Bridge Test", "Fixtures"])
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
        app.launchArguments = ["--double-hook"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Injected framework 0.7.0"].waitForExistence(timeout: 10))
        app.buttons["harnessImage"].tap()
        app.buttons["Browse Files"].tap()
        let cancel = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        cancel.tap()
        expectation(for: NSPredicate(format: "label == %@", "PASS cancel; presenter=yes; dismiss=yes"), evaluatedWith: app.staticTexts["harnessResult"])
        waitForExpectations(timeout: 20)
    }
    private func launchInjected() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--double-hook"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Injected framework 0.7.0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pickerPatcherStatus"].waitForExistence(timeout:5))
        return app
    }
    func testPHPickerFilesProvidersAndSwiftBridge() {
        let app=launchInjected()
        app.buttons["harnessPHPicker"].tap()
        XCTAssertTrue(app.buttons["Browse Files"].waitForExistence(timeout: 10))
        app.buttons["Browse Files"].tap()
        selectNativeFile(app,name:"PickerBridge.png",folders:["Picker Bridge Test","Fixtures"])
        let expected="PASS providers; count=1; object=yes; data=yes; file=yes; identities=nil; dismiss=yes; swift=yes"
        expectation(for:NSPredicate(format:"label == %@",expected),evaluatedWith:app.staticTexts["harnessResult"])
        waitForExpectations(timeout:30)
    }
    func testPHPickerFilesMultipleSelection() {
        let app=launchInjected()
        app.buttons["harnessPHMultiple"].tap()
        app.buttons["Browse Files"].tap()
        selectNativeFile(app,name:"PickerBridge.png",folders:["Picker Bridge Test","Fixtures"])
        let second=app.collectionViews.cells.matching(NSPredicate(format:"label BEGINSWITH %@","PickerBridge2")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout:10))
        second.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
        let open=app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout:5)); open.tap()
        let expected="PASS providers; count=2; object=yes; data=yes; file=yes; identities=nil; dismiss=yes; swift=yes"
        expectation(for:NSPredicate(format:"label == %@",expected),evaluatedWith:app.staticTexts["harnessResult"])
        waitForExpectations(timeout:30)
    }
    func testPHPickerFilesCancellation() {
        let app=launchInjected()
        app.buttons["harnessPHPicker"].tap()
        app.buttons["Browse Files"].tap()
        let cancel=app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout:15)); cancel.tap()
        expectation(for:NSPredicate(format:"label == %@","PASS php cancel; presenter=yes; dismiss=yes"),evaluatedWith:app.staticTexts["harnessResult"])
        waitForExpectations(timeout:20)
    }
    func testContainedImagePicker() {
        let app=launchInjected()
        app.buttons["harnessWrapped"].tap()
        XCTAssertTrue(app.buttons["Browse Files"].waitForExistence(timeout:10))
        app.buttons["Browse Files"].tap()
        selectNativeFile(app,name:"PickerBridge.png",folders:["Picker Bridge Test","Fixtures"])
        expectation(for:NSPredicate(format:"label BEGINSWITH %@","PASS image; presenter=yes; dismiss=yes; bytes="),evaluatedWith:app.staticTexts["harnessResult"])
        waitForExpectations(timeout:25)
    }
    func testWebKitNativeFileUpload() {
        let app=launchInjected()
        app.buttons["harnessWeb"].tap()
        let input=app.webViews.buttons["Choose upload image"]
        XCTAssertTrue(input.waitForExistence(timeout:20)); input.tap()
        selectNativeFile(app,name:"PickerBridge.png",folders:["Picker Bridge Test","Fixtures"])
        expectation(for:NSPredicate(format:"label == %@","PASS web; input change=yes; bytes=yes; image decode=yes"),evaluatedWith:app.staticTexts["webResult"])
        waitForExpectations(timeout:25)
    }

}

// directoryURL is a suggested starting location. Files may show the parent
// container on a fresh installation. Navigate visible folders through its UI.
private func selectNativeFile(_ app: XCUIApplication, name: String, folders: [String], file: StaticString = #filePath, line: UInt = #line) {
    let stem = (name as NSString).deletingPathExtension
    let picked = app.collectionViews.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", name, stem)).firstMatch
    for folder in folders {
        if picked.waitForExistence(timeout: 2) { break }
        let entry = app.collectionViews.staticTexts.matching(NSPredicate(format: "label == %@", folder)).firstMatch
        if entry.waitForExistence(timeout: 5) {
            let folderCell = app.collectionViews.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", folder, folder + ",")).firstMatch
            XCTAssertTrue(folderCell.isHittable, "Native folder icon must be on screen", file: file, line: line)
            folderCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        }
    }
    XCTAssertTrue(picked.waitForExistence(timeout: 20), "Native Files must show \(name). Hierarchy: \(app.debugDescription)", file: file, line: line)
    let cell = app.collectionViews.cells.matching(NSPredicate(format: "label == %@ OR label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", name, stem, name + ",", stem + ",")).firstMatch
    XCTAssertTrue(cell.isHittable, "Native file icon must be on screen", file: file, line: line)
    XCTAssertTrue(cell.isEnabled, "Files must enable the selected entry", file: file, line: line)
    cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
}
