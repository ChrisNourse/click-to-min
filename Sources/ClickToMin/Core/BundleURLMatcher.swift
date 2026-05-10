import Foundation

/// Compares two bundle URLs with normalization.
///
/// Normalization: `standardizedFileURL` then `resolvingSymlinksInPath()`,
/// which also strips trailing slashes and resolves `file://` scheme to
/// a file path URL.
///
/// Does **not** case-fold — case-sensitive volumes must compare exactly.
/// `/Applications/safari.app` ≠ `/Applications/Safari.app`.
public enum BundleURLMatcher {
    /// Returns `true` if both URLs resolve to the same normalized path.
    /// Returns `false` if either URL is nil — Finder, Trash, stacks,
    /// and separators have no bundle URL and should never match.
    public static func matches(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        return normalize(lhs) == normalize(rhs)
    }

    private static func normalize(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
