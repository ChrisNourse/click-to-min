import XCTest
@testable import ClickToMinCore

final class SettingsTests: XCTestCase {

    // MARK: - In-memory fake

    final class FakeSettingsStore: SettingsStore {
        var enabled: Bool = true
        var iconHidden: Bool = false
    }

    // MARK: - Protocol defaults

    func testDefaultEnabled() {
        let store = FakeSettingsStore()
        XCTAssertTrue(store.enabled)
    }

    func testDefaultIconHidden() {
        let store = FakeSettingsStore()
        XCTAssertFalse(store.iconHidden)
    }

    // MARK: - Round-trip

    func testEnabledRoundTrip() {
        let store = FakeSettingsStore()
        store.enabled = false
        XCTAssertFalse(store.enabled)
        store.enabled = true
        XCTAssertTrue(store.enabled)
    }

    func testIconHiddenRoundTrip() {
        let store = FakeSettingsStore()
        store.iconHidden = true
        XCTAssertTrue(store.iconHidden)
        store.iconHidden = false
        XCTAssertFalse(store.iconHidden)
    }

    // MARK: - Keys

    func testKeyStringsNonEmpty() {
        XCTAssertFalse(SettingsKeys.enabled.isEmpty)
        XCTAssertFalse(SettingsKeys.iconHidden.isEmpty)
        XCTAssertFalse(SettingsKeys.hideAcknowledged.isEmpty)
    }

    func testKeysArePrefixed() {
        XCTAssertTrue(SettingsKeys.enabled.hasPrefix("com.click-to-min."))
        XCTAssertTrue(SettingsKeys.iconHidden.hasPrefix("com.click-to-min."))
        XCTAssertTrue(SettingsKeys.hideAcknowledged.hasPrefix("com.click-to-min."))
    }
}
