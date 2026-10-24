import SwiftUI

/// Builds a `Path` from SVG path data so brand marks can be embedded as the
/// vendor ships them. Supports the commands Illustrator exports for flat
/// marks: M/m, L/l, H/h, V/v, C/c, S/s and Z/z, with implicit repeats and
/// the compact number forms `-.5-.5` and `.5.5`. Exponents and arcs are not
/// supported.
enum SVGPath {
    static func path(_ data: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"
        var numbers: [CGFloat] = []

        func point(_ x: CGFloat, _ y: CGFloat, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        func apply() {
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                guard numbers.count >= 2 else { return }
                current = point(numbers[0], numbers[1], relative: relative)
                subpathStart = current
                path.move(to: current)
                numbers.removeFirst(2)
                command = relative ? "l" : "L"
                lastControl = nil
                apply()
            case "L":
                guard numbers.count >= 2 else { return }
                current = point(numbers[0], numbers[1], relative: relative)
                path.addLine(to: current)
                numbers.removeFirst(2)
                lastControl = nil
                apply()
            case "H":
                guard numbers.count >= 1 else { return }
                current = CGPoint(x: relative ? current.x + numbers[0] : numbers[0], y: current.y)
                path.addLine(to: current)
                numbers.removeFirst(1)
                lastControl = nil
                apply()
            case "V":
                guard numbers.count >= 1 else { return }
                current = CGPoint(x: current.x, y: relative ? current.y + numbers[0] : numbers[0])
                path.addLine(to: current)
                numbers.removeFirst(1)
                lastControl = nil
                apply()
            case "C":
                guard numbers.count >= 6 else { return }
                let control1 = point(numbers[0], numbers[1], relative: relative)
                let control2 = point(numbers[2], numbers[3], relative: relative)
                let end = point(numbers[4], numbers[5], relative: relative)
                path.addCurve(to: end, control1: control1, control2: control2)
                current = end
                lastControl = control2
                numbers.removeFirst(6)
                apply()
            case "S":
                guard numbers.count >= 4 else { return }
                let reflected = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let control2 = point(numbers[0], numbers[1], relative: relative)
                let end = point(numbers[2], numbers[3], relative: relative)
                path.addCurve(to: end, control1: reflected, control2: control2)
                current = end
                lastControl = control2
                numbers.removeFirst(4)
                apply()
            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
            default:
                numbers.removeAll()
            }
        }

        var pending = ""
        var seenDot = false

        func flushNumber() {
            if let value = Double(pending) {
                numbers.append(CGFloat(value))
            }
            pending = ""
            seenDot = false
        }

        for character in data {
            if character.isLetter {
                flushNumber()
                apply()
                command = character
                numbers.removeAll()
                if character.uppercased() == "Z" {
                    apply()
                }
            } else if character == "," || character.isWhitespace {
                flushNumber()
            } else if character == "-" {
                if !pending.isEmpty {
                    flushNumber()
                }
                pending.append(character)
            } else if character == "." {
                if seenDot {
                    flushNumber()
                }
                seenDot = true
                pending.append(character)
            } else {
                pending.append(character)
            }
        }
        flushNumber()
        apply()

        return path
    }

    /// Scales `path`, drawn in a `viewBox` coordinate space, to fit `rect`
    /// without distortion and centres it.
    static func fit(_ path: Path, viewBox: CGSize, in rect: CGRect) -> Path {
        guard viewBox.width > 0, viewBox.height > 0 else { return path }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let offset = CGPoint(
            x: rect.minX + (rect.width - viewBox.width * scale) / 2,
            y: rect.minY + (rect.height - viewBox.height * scale) / 2
        )
        let transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }
}
