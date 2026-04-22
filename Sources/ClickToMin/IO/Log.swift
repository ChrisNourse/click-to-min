import os.log

/// Shared `os_log` handles for ClickToMin diagnostics.
///
/// Usage: `os_log("monitor installed", log: Log.lifecycle, type: .info)`
///
/// Surface at runtime with:
///   log stream --predicate 'subsystem == "com.chrisno.click-to-min"'
enum Log {
    static let lifecycle = OSLog(subsystem: "com.chrisno.click-to-min", category: "lifecycle")
    static let pipeline = OSLog(subsystem: "com.chrisno.click-to-min", category: "pipeline")
}
