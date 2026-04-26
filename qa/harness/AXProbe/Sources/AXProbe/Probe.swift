import Foundation

/// Exit codes documented for use by `qa/*.sh` callers:
///   0 = success / predicate true
///   1 = generic failure (bad args, AX query failed, predicate false)
///   2 = timeout (wait-until-* only)
///   3 = Accessibility not granted
public enum Probe {
    public static let grantHint: String = """
    Accessibility permission missing.
    Grant via: System Settings -> Privacy & Security -> Accessibility
    Add the axprobe binary (this executable, not ClickToMin.app).
    """

    public static func run(args: [String], reader: AXReader) -> Int32 {
        guard let cmd = args.first else {
            printUsage()
            return 1
        }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "is-trusted":
            return reader.isProcessTrusted() ? 0 : 3
        case "frontmost-bundle-id":
            guard let bid = reader.frontmostBundleId() else {
                FileHandle.standardError.write(Data("no frontmost application\n".utf8))
                return 1
            }
            print(bid)
            return 0
        case "is-minimized":
            return isMinimized(rest: rest, reader: reader)
        case "window-count":
            return windowCount(rest: rest, reader: reader)
        case "wait-until-minimized":
            return waitUntilMinimized(rest: rest, reader: reader)
        case "dock-item-frame":
            return dockItemFrame(rest: rest, reader: reader)
        case "-h", "--help", "help":
            printUsage()
            return 0
        default:
            FileHandle.standardError.write(Data("unknown subcommand: \(cmd)\n".utf8))
            printUsage()
            return 1
        }
    }

    // MARK: - subcommand handlers

    private static func isMinimized(rest: [String], reader: AXReader) -> Int32 {
        guard let bid = rest.first else {
            FileHandle.standardError.write(Data("usage: axprobe is-minimized <bundle-id>\n".utf8))
            return 1
        }
        guard reader.isProcessTrusted() else {
            FileHandle.standardError.write(Data(grantHint.utf8))
            return 3
        }
        guard let minimized = reader.focusedWindowMinimized(bundleId: bid) else {
            FileHandle.standardError.write(Data("no focused window for \(bid)\n".utf8))
            return 1
        }
        print("minimized=\(minimized)")
        return 0
    }

    private static func windowCount(rest: [String], reader: AXReader) -> Int32 {
        guard let bid = rest.first else {
            FileHandle.standardError.write(Data("usage: axprobe window-count <bundle-id>\n".utf8))
            return 1
        }
        guard reader.isProcessTrusted() else {
            FileHandle.standardError.write(Data(grantHint.utf8))
            return 3
        }
        guard let count = reader.windowCount(bundleId: bid) else {
            FileHandle.standardError.write(Data("app not running or AX query failed: \(bid)\n".utf8))
            return 1
        }
        print(count)
        return 0
    }

    private static func waitUntilMinimized(rest: [String], reader: AXReader) -> Int32 {
        guard let bid = rest.first else {
            FileHandle.standardError.write(
                Data("usage: axprobe wait-until-minimized <bundle-id> [--timeout SECS]\n".utf8)
            )
            return 1
        }
        guard reader.isProcessTrusted() else {
            FileHandle.standardError.write(Data(grantHint.utf8))
            return 3
        }
        var timeout: Double = 2.0
        var i = 1
        while i < rest.count {
            if rest[i] == "--timeout", i + 1 < rest.count, let parsed = Double(rest[i + 1]) {
                timeout = parsed
                i += 2
            } else {
                i += 1
            }
        }
        let pollInterval: Double = 0.025
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if reader.anyWindowMinimized(bundleId: bid) == true {
                print("minimized=true")
                return 0
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        FileHandle.standardError.write(Data("timeout after \(timeout)s\n".utf8))
        return 2
    }

    private static func dockItemFrame(rest: [String], reader: AXReader) -> Int32 {
        guard let bid = rest.first else {
            FileHandle.standardError.write(Data("usage: axprobe dock-item-frame <bundle-id>\n".utf8))
            return 1
        }
        guard reader.isProcessTrusted() else {
            FileHandle.standardError.write(Data(grantHint.utf8))
            return 3
        }
        guard let frame = reader.dockItemFrame(bundleId: bid) else {
            FileHandle.standardError.write(Data("dock item not found for \(bid)\n".utf8))
            return 1
        }
        print("x=\(frame.origin.x) y=\(frame.origin.y) w=\(frame.size.width) h=\(frame.size.height)")
        return 0
    }

    private static func printUsage() {
        let usage = """
        axprobe — AX assertion CLI for ClickToMin QA

        Subcommands:
          is-trusted
              Exit 0 if Accessibility is granted, 3 otherwise.
          frontmost-bundle-id
              Print NSWorkspace.shared.frontmostApplication.bundleIdentifier.
          is-minimized <bundle-id>
              Print "minimized=true|false" for the focused window.
          window-count <bundle-id>
              Print the visible window count for the app.
          wait-until-minimized <bundle-id> [--timeout SECS]
              Poll at 25ms; exit 0 on minimized, 2 on timeout. Default 2s.
          dock-item-frame <bundle-id>
              Print "x= y= w= h=" for the Dock tile matching the bundle id.
        """
        print(usage)
    }
}
