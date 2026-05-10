import CoreGraphics

enum TestClickMode {
    case normal
    case right
    case ctrl
    case rapid(count: Int)
}

struct TestClickSpec {
    let point: CGPoint
    let mode: TestClickMode

    static func parse(_ raw: String) -> TestClickSpec? {
        let segments = raw.split(separator: ":")
        guard !segments.isEmpty else { return nil }
        let coordParts = segments[0].split(separator: ",")
        guard coordParts.count == 2,
              let xVal = Double(coordParts[0]),
              let yVal = Double(coordParts[1]) else { return nil }
        let point = CGPoint(x: xVal, y: yVal)

        if segments.count == 1 {
            return TestClickSpec(point: point, mode: .normal)
        }

        let modifier = segments[1].lowercased()
        switch modifier {
        case "right":
            return TestClickSpec(point: point, mode: .right)
        case "ctrl":
            return TestClickSpec(point: point, mode: .ctrl)
        case "rapid":
            guard segments.count >= 3, let count = Int(segments[2]), count > 0 else {
                return TestClickSpec(point: point, mode: .rapid(count: 3))
            }
            return TestClickSpec(point: point, mode: .rapid(count: count))
        default:
            return nil
        }
    }
}
