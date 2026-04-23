import XCTest

@testable import ClickToMinCore

final class DockItemClassificationTests: XCTestCase {

    // MARK: - isDockItemRole

    func testIsDockItemRole_exactMatch() {
        XCTAssertTrue(DockItemClassification.isDockItemRole("AXDockItem"))
    }

    func testIsDockItemRole_nil() {
        XCTAssertFalse(DockItemClassification.isDockItemRole(nil))
    }

    func testIsDockItemRole_otherRole() {
        XCTAssertFalse(DockItemClassification.isDockItemRole("AXButton"))
        XCTAssertFalse(DockItemClassification.isDockItemRole("AXList"))
    }

    func testIsDockItemRole_caseMatters() {
        XCTAssertFalse(DockItemClassification.isDockItemRole("axdockitem"))
    }

    // MARK: - isDockItemSubrole

    func testIsDockItemSubrole_applicationDockItem() {
        XCTAssertTrue(DockItemClassification.isDockItemSubrole("AXApplicationDockItem"))
    }

    func testIsDockItemSubrole_separatorDockItem() {
        XCTAssertTrue(DockItemClassification.isDockItemSubrole("AXSeparatorDockItem"))
    }

    func testIsDockItemSubrole_nil() {
        XCTAssertFalse(DockItemClassification.isDockItemSubrole(nil))
    }

    func testIsDockItemSubrole_noSuffix() {
        XCTAssertFalse(DockItemClassification.isDockItemSubrole("AXButton"))
        XCTAssertFalse(DockItemClassification.isDockItemSubrole("AXStandardWindow"))
    }

    // MARK: - isDockItem (combined)

    func testIsDockItem_roleMatch() {
        XCTAssertTrue(DockItemClassification.isDockItem(role: "AXDockItem", subrole: nil))
    }

    func testIsDockItem_subroleMatch() {
        XCTAssertTrue(DockItemClassification.isDockItem(role: "AXGroup", subrole: "AXApplicationDockItem"))
    }

    func testIsDockItem_bothMatch() {
        XCTAssertTrue(DockItemClassification.isDockItem(role: "AXDockItem", subrole: "AXApplicationDockItem"))
    }

    func testIsDockItem_neitherMatch() {
        XCTAssertFalse(DockItemClassification.isDockItem(role: "AXButton", subrole: "AXStandardWindow"))
    }

    func testIsDockItem_bothNil() {
        XCTAssertFalse(DockItemClassification.isDockItem(role: nil, subrole: nil))
    }

    // MARK: - isExcluded

    func testIsExcluded_separator() {
        XCTAssertTrue(DockItemClassification.isExcluded(subrole: "AXSeparatorDockItem"))
    }

    func testIsExcluded_folder() {
        XCTAssertTrue(DockItemClassification.isExcluded(subrole: "AXFolderDockItem"))
    }

    func testIsExcluded_trash() {
        XCTAssertTrue(DockItemClassification.isExcluded(subrole: "AXTrashDockItem"))
    }

    func testIsExcluded_minimizedWindow() {
        XCTAssertTrue(DockItemClassification.isExcluded(subrole: "AXMinimizedWindowDockItem"))
    }

    func testIsExcluded_desktop() {
        XCTAssertTrue(DockItemClassification.isExcluded(subrole: "AXDesktopDockItem"))
    }

    func testIsExcluded_applicationDockItem_notExcluded() {
        XCTAssertFalse(DockItemClassification.isExcluded(subrole: "AXApplicationDockItem"))
    }

    func testIsExcluded_nil() {
        XCTAssertFalse(DockItemClassification.isExcluded(subrole: nil))
    }

    func testIsExcluded_unknownSubrole() {
        XCTAssertFalse(DockItemClassification.isExcluded(subrole: "AXSomethingElse"))
    }

    // MARK: - excludedSubroles set completeness

    func testExcludedSubroles_containsExactlyFive() {
        XCTAssertEqual(DockItemClassification.excludedSubroles.count, 5)
    }
}
