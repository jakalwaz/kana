import Foundation

/// Small helpers for building terminal output by hand.
public enum Ansi {
    public static let reset = "\u{1B}[0m"
    public static let bold = "\u{1B}[1m"

    public static func fg(_ c: RGB) -> String {
        "\u{1B}[38;2;\(c.r);\(c.g);\(c.b)m"
    }

    public static func paint(_ text: String, _ c: RGB, bold: Bool = false) -> String {
        (bold ? Ansi.bold : "") + fg(c) + text + reset
    }

    /// In the terminal's own foreground, so it reads on any theme, light or dark.
    public static func plain(_ text: String, bold: Bool = false) -> String {
        (bold ? Ansi.bold : "") + text + reset
    }

    /// Columns a string takes on screen: escape sequences take none, East
    /// Asian wide characters (カナ) take two.
    public static func visibleWidth(_ s: String) -> Int {
        var width = 0
        var inEscape = false
        for scalar in s.unicodeScalars {
            if inEscape {
                // CSI ends with a letter
                if (0x40 ... 0x7E).contains(scalar.value), scalar != "[" { inEscape = false }
                continue
            }
            if scalar == "\u{1B}" { inEscape = true; continue }
            width += columns(of: scalar)
        }
        return width
    }

    static func columns(of scalar: Unicode.Scalar) -> Int {
        let v = scalar.value
        if v < 0x20 { return 0 }
        if (0x0300 ... 0x036F).contains(v) || v == 0x200D || (0xFE00 ... 0xFE0F).contains(v) { return 0 }
        let wide: [ClosedRange<UInt32>] = [
            0x1100 ... 0x115F, 0x2E80 ... 0x303E, 0x3041 ... 0x33FF, 0x3400 ... 0x4DBF,
            0x4E00 ... 0x9FFF, 0xA000 ... 0xA4CF, 0xAC00 ... 0xD7A3, 0xF900 ... 0xFAFF,
            0xFE30 ... 0xFE4F, 0xFF00 ... 0xFF60, 0xFFE0 ... 0xFFE6, 0x1F300 ... 0x1FAFF,
        ]
        return wide.contains { $0.contains(v) } ? 2 : 1
    }

    /// Pads with spaces (or cuts, keeping escapes intact) to exactly `width` columns.
    public static func fit(_ s: String, _ width: Int, align: Align = .left) -> String {
        let w = visibleWidth(s)
        if w == width { return s }
        if w < width {
            let gap = width - w
            switch align {
            case .left: return s + String(repeating: " ", count: gap)
            case .right: return String(repeating: " ", count: gap) + s
            case .center:
                let left = gap / 2
                return String(repeating: " ", count: left) + s + String(repeating: " ", count: gap - left)
            }
        }
        return truncate(s, width)
    }

    public enum Align { case left, center, right }

    /// Cuts to `width` columns, ending with … when anything was dropped.
    public static func truncate(_ s: String, _ width: Int) -> String {
        guard width > 0 else { return "" }
        var out = ""
        var used = 0
        var inEscape = false
        for scalar in s.unicodeScalars {
            if inEscape {
                out.unicodeScalars.append(scalar)
                if (0x40 ... 0x7E).contains(scalar.value), scalar != "[" { inEscape = false }
                continue
            }
            if scalar == "\u{1B}" { inEscape = true; out.unicodeScalars.append(scalar); continue }
            let c = columns(of: scalar)
            if used + c > width - 1 {
                // room for the ellipsis
                out += "…"
                used += 1
                break
            }
            out.unicodeScalars.append(scalar)
            used += c
        }
        return out + reset + String(repeating: " ", count: max(0, width - used))
    }
}

public struct RGB: Sendable, Equatable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    /// Linear mix toward `other`, t in 0...1.
    public func mix(_ other: RGB, _ t: Double) -> RGB {
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(a) * (1 - t) + Double(b) * t).rounded()))) }
        return RGB(m(r, other.r), m(g, other.g), m(b, other.b))
    }

    public static let white = RGB(0xE6, 0xE6, 0xE6)
    public static let grey = RGB(0x8C, 0x8C, 0x8C)
    public static let dim = RGB(0x55, 0x55, 0x55)
    public static let black = RGB(0, 0, 0)
}
