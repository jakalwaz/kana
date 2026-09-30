import Foundation
import KanaSkins

/// Shrinks a `.kana` clip to fit a smaller grid. Each character stands for a
/// brightness (its place in the converter's ramp), so a block of source cells
/// is averaged as brightness and colour, then mapped back to a character.
public enum AsciiResampler {
    /// Same ramps as tools/ascii/convert.py, darkest first.
    static let ramps = [
        " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
        " .:-=+*#%@",
        " ░▒▓█",
        " ·•●",
    ]
    static let outRamp = Array(ramps[0])

    static let density: [Character: Double] = {
        var table: [Character: Double] = [:]
        // later ramps first so the detailed ramp wins on shared characters
        for ramp in ramps.reversed() {
            let chars = Array(ramp)
            for (i, ch) in chars.enumerated() {
                table[ch] = Double(i) / Double(chars.count - 1)
            }
        }
        return table
    }()

    /// Drops rows and columns that are blank in every frame, so the subject
    /// fills the space it's given.
    public static func trimmed(_ clip: KanaClip) -> KanaClip {
        var top = clip.height, bottom = -1, left = clip.width, right = -1
        for frame in clip.frames {
            for (y, row) in frame.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != " " {
                    top = min(top, y); bottom = max(bottom, y)
                    left = min(left, x); right = max(right, x)
                }
            }
        }
        guard bottom >= top, right >= left else { return clip }
        if top == 0, left == 0, bottom == clip.height - 1, right == clip.width - 1 { return clip }
        let width = right - left + 1, height = bottom - top + 1
        let frames = clip.frames.map { frame -> KanaFrame in
            let rows = frame.rows[top ... bottom].map { String(Array($0)[left ... right]) }
            var colors: Data?
            if clip.hasColor {
                var out = Data(capacity: width * height * 3)
                for y in top ... bottom {
                    for x in left ... right {
                        let c = frame.color(x: x, y: y, width: clip.width) ?? (0, 0, 0)
                        out.append(contentsOf: [c.r, c.g, c.b])
                    }
                }
                colors = out
            }
            return KanaFrame(rows: rows, colors: colors)
        }
        return KanaClip(width: width, height: height, fps: clip.fps, hasColor: clip.hasColor,
                        portraitIndex: clip.portraitIndex, frames: frames)
    }

    /// Drops the empty rows above the subject in the resting frame, so the
    /// picture it settles on sits right under whatever is above it. Earlier
    /// frames lose the same rows; the bottom is never cut.
    public static func trimmedTopForRest(_ clip: KanaClip) -> KanaClip {
        let rest = clip.portrait.rows
        let empty = rest.prefix { $0.allSatisfy { $0 == " " } }.count
        guard empty > 0, empty < clip.height - 4 else { return clip }
        return cropped(clip, top: empty, count: clip.height - empty)
    }

    /// Keeps `count` rows starting at `top`, like a letterbox crop.
    public static func cropped(_ clip: KanaClip, top: Int, count: Int) -> KanaClip {
        let top = max(0, min(top, clip.height - 1))
        let count = max(1, min(count, clip.height - top))
        if top == 0, count == clip.height { return clip }
        let frames = clip.frames.map { frame -> KanaFrame in
            let rows = Array(frame.rows[top ..< top + count])
            let colors = frame.colors.map { data in
                let start = data.startIndex + top * clip.width * 3
                return Data(data[start ..< start + count * clip.width * 3])
            }
            return KanaFrame(rows: rows, colors: colors)
        }
        return KanaClip(width: clip.width, height: count, fps: clip.fps, hasColor: clip.hasColor,
                        portraitIndex: clip.portraitIndex, frames: frames)
    }

    /// The row where the strongest colour sits in `frame` (a red bike on a
    /// grey trail), so a crop can keep it in view.
    public static func focusRow(of frame: KanaFrame, width: Int) -> Int {
        guard frame.colors != nil else { return frame.rows.count / 2 }
        var total = 0.0, weighted = 0.0
        for y in frame.rows.indices {
            var rowWeight = 0.0
            for x in 0 ..< width {
                guard let c = frame.color(x: x, y: y, width: width) else { continue }
                let hi = Double(max(c.r, c.g, c.b)), lo = Double(min(c.r, c.g, c.b))
                guard hi > 0 else { continue }
                rowWeight += max(0, (hi - lo) / hi - 0.5) * (hi / 255)
            }
            total += rowWeight
            weighted += rowWeight * Double(y)
        }
        return total > 0 ? Int(weighted / total) : frame.rows.count / 2
    }

    public static func resample(_ clip: KanaClip, width: Int, height: Int) -> KanaClip {
        guard width > 0, height > 0 else { return clip }
        if width == clip.width, height == clip.height { return clip }
        let frames = clip.frames.map { resample(frame: $0, from: clip, width: width, height: height) }
        return KanaClip(width: width, height: height, fps: clip.fps, hasColor: clip.hasColor,
                        portraitIndex: clip.portraitIndex, frames: frames)
    }

    static func resample(frame: KanaFrame, from clip: KanaClip, width: Int, height: Int) -> KanaFrame {
        let grid = frame.rows.map { Array($0) }
        var rows: [String] = []
        rows.reserveCapacity(height)
        var colors = clip.hasColor ? Data(capacity: width * height * 3) : nil

        for ty in 0 ..< height {
            let y0 = ty * clip.height / height
            let y1 = max(y0 + 1, (ty + 1) * clip.height / height)
            var row = ""
            for tx in 0 ..< width {
                let x0 = tx * clip.width / width
                let x1 = max(x0 + 1, (tx + 1) * clip.width / width)
                var sum = 0.0, peak = 0.0, weight = 0.0
                var r = 0.0, g = 0.0, b = 0.0
                var count = 0.0
                for y in y0 ..< min(y1, clip.height) {
                    for x in x0 ..< min(x1, clip.width) {
                        count += 1
                        let d = density[grid[y][x]] ?? (grid[y][x] == " " ? 0 : 0.5)
                        guard d > 0 else { continue }
                        sum += d
                        peak = max(peak, d)
                        if let c = frame.color(x: x, y: y, width: clip.width) {
                            r += Double(c.r) * d; g += Double(c.g) * d; b += Double(c.b) * d
                            weight += d
                        }
                    }
                }
                // between the mean and the peak, so thin bright lines survive shrinking
                // and lifted slightly, since averaging dulls a little
                let d = count > 0 ? pow(min(1, 0.55 * (sum / count) + 0.45 * peak), 0.9) : 0
                let index = Int((d * Double(outRamp.count - 1)).rounded())
                row.append(d < 0.02 ? " " : outRamp[max(1, index)])
                if colors != nil {
                    let w = max(weight, 1e-9)
                    let rgb = [r / w, g / w, b / w]
                    colors!.append(contentsOf: rgb.map { UInt8(min(255, $0.rounded())) })
                }
            }
            rows.append(row)
        }
        return KanaFrame(rows: rows, colors: colors)
    }
}
