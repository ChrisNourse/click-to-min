import Foundation

@main
enum AXProbeMain {
    static func main() {
        // When launched via `open -W -a AXProbe.app --args ...`, there's no
        // attached terminal, so stdout/stderr go to /dev/null and the caller
        // can't read them. Also, `open`'s exit code forwarding is flaky (see
        // the "Unable to block on application" warning). Support optional
        // sidecar file paths so the shell wrapper at /usr/local/bin/axprobe
        // can reliably capture output and exit status:
        //
        //   axprobe --output-file /tmp/out --output-stderr /tmp/err \
        //           --exit-file /tmp/rc <real subcommand and args...>
        //
        // These flags are stripped before dispatching to Probe.run; Probe.run
        // sees only its real subcommand+args, unchanged.
        var args = Array(CommandLine.arguments.dropFirst())
        var outputPath: String?
        var errorPath: String?
        var exitPath: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--output-file" where i + 1 < args.count:
                outputPath = args[i + 1]
                args.removeSubrange(i..<i + 2)
            case "--output-stderr" where i + 1 < args.count:
                errorPath = args[i + 1]
                args.removeSubrange(i..<i + 2)
            case "--exit-file" where i + 1 < args.count:
                exitPath = args[i + 1]
                args.removeSubrange(i..<i + 2)
            default:
                i += 1
            }
        }

        if let path = outputPath {
            _ = freopen(path, "w", stdout)
            setvbuf(stdout, nil, _IONBF, 0)
        }
        if let path = errorPath {
            _ = freopen(path, "w", stderr)
            setvbuf(stderr, nil, _IONBF, 0)
        }

        let reader = SystemAXReader()
        let rc = Probe.run(args: args, reader: reader)

        fflush(stdout)
        fflush(stderr)

        if let path = exitPath {
            try? "\(rc)\n".write(toFile: path, atomically: true, encoding: .utf8)
        }

        exit(rc)
    }
}
