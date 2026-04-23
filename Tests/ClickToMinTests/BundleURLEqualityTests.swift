import XCTest
@testable import ClickToMinCore

final class BundleURLEqualityTests: XCTestCase {

    // MARK: - Trailing slash normalization

    func testTrailingSlash_matches() {
        let a = URL(fileURLWithPath: "/Applications/Safari.app/")
        let b = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertTrue(BundleURLMatcher.matches(a, b))
    }

    func testTrailingSlash_reversed() {
        let a = URL(fileURLWithPath: "/Applications/Safari.app")
        let b = URL(fileURLWithPath: "/Applications/Safari.app/")
        XCTAssertTrue(BundleURLMatcher.matches(a, b))
    }

    // MARK: - file:// URL form

    /// A URL constructed from a string with "file://" scheme should match
    /// the same path constructed via fileURLWithPath.
    func testFileSchemeURL_matches() {
        let a = URL(string: "file:///Applications/Safari.app")!
        let b = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertTrue(BundleURLMatcher.matches(a, b))
    }

    // MARK: - Nil safety

    func testNilFirst_returnsFalse() {
        let b = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertFalse(BundleURLMatcher.matches(nil, b))
    }

    func testNilSecond_returnsFalse() {
        let a = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertFalse(BundleURLMatcher.matches(a, nil))
    }

    func testBothNil_returnsFalse() {
        XCTAssertFalse(BundleURLMatcher.matches(nil, nil))
    }

    // MARK: - Case-sensitive (no case folding)

    /// `/nonexistent/safari.app` ≠ `/nonexistent/Safari.app`.
    /// Uses a path that does not exist on disk so the case distinction
    /// survives normalization. On APFS (case-insensitive-case-preserving)
    /// `resolvingSymlinksInPath()` would canonicalize cased variants of a
    /// real path to the same on-disk form, which defeats the intent.
    func testCaseSensitive_doesNotMatch() {
        let a = URL(fileURLWithPath: "/nonexistent-click-to-min/safari.app")
        let b = URL(fileURLWithPath: "/nonexistent-click-to-min/Safari.app")
        XCTAssertFalse(BundleURLMatcher.matches(a, b))
    }

    // MARK: - Symlink resolution (real filesystem test)

    /// Creates a temporary symlink and verifies that the matcher resolves
    /// it to the same normalized path as the real target.
    func testSymlink_resolvesToRealPath() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        defer { try? fm.removeItem(at: tmp) }

        let realDir = tmp.appendingPathComponent("Real.app")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)

        let symlinkPath = tmp.appendingPathComponent("Link.app").path
        try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: realDir.path)

        let symlinkURL = URL(fileURLWithPath: symlinkPath)

        XCTAssertTrue(BundleURLMatcher.matches(realDir, symlinkURL))
        XCTAssertTrue(BundleURLMatcher.matches(symlinkURL, realDir))
    }

    // MARK: - Property-style: matches(x, x) true for non-nil

    func testSelfMatch_alwaysTrue() {
        let urls: [URL] = [
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/usr/bin/env"),
            URL(string: "file:///tmp/Foo.app")!,
            URL(fileURLWithPath: "/Applications/Utilities/Terminal.app/"),
        ]
        for url in urls {
            XCTAssertTrue(
                BundleURLMatcher.matches(url, url),
                "Expected matches(x, x) to be true for \(url)"
            )
        }
    }

    // MARK: - matches(nil, x) false for any x

    func testNilFirstWithVariousSecond_allFalse() {
        let urls: [URL] = [
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/tmp"),
        ]
        for url in urls {
            XCTAssertFalse(
                BundleURLMatcher.matches(nil, url),
                "Expected matches(nil, x) to be false for \(url)"
            )
        }
    }

    // MARK: - Distinct paths don't match

    func testDifferentPaths_dontMatch() {
        let a = URL(fileURLWithPath: "/Applications/Safari.app")
        let b = URL(fileURLWithPath: "/Applications/TextEdit.app")
        XCTAssertFalse(BundleURLMatcher.matches(a, b))
    }
}
