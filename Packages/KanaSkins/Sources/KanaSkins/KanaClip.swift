import Foundation

/// One frame of a `.kana` clip: `height` rows of `width` characters, plus
/// optional RGB colour per cell.
public struct KanaFrame: Sendable {
    public let rows: [String]
    /// `width * height * 3` RGB bytes, row by row. `nil` if the clip has no colour.
    public let colors: Data?

    public init(rows: [String], colors: Data?) {
        self.rows = rows
        self.colors = colors
    }

    public func color(x: Int, y: Int, width: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let colors, x >= 0, y >= 0, x < width else { return nil }
        let i = (y * width + x) * 3
        guard i + 2 < colors.count else { return nil }
        return colors.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            return (p[i], p[i + 1], p[i + 2])
        }
    }
}

public struct KanaClip: Sendable {
    public let width: Int
    public let height: Int
    /// 0 for a still image.
    public let fps: Int
    public let hasColor: Bool
    public let portraitIndex: Int
    public let frames: [KanaFrame]

    public init(width: Int, height: Int, fps: Int, hasColor: Bool, portraitIndex: Int, frames: [KanaFrame]) {
        self.width = width
        self.height = height
        self.fps = fps
        self.hasColor = hasColor
        self.portraitIndex = portraitIndex
        self.frames = frames
    }

    public var portrait: KanaFrame { frames[portraitIndex] }

    /// 0 for a still.
    public var duration: TimeInterval {
        fps > 0 ? TimeInterval(frames.count) / TimeInterval(fps) : 0
    }
}

public enum KanaClipError: Error, Equatable {
    case unreadable
    case notKanaFile
    case unsupportedVersion(Int)
    case malformed(String)
}

public enum KanaClipLoader {
    static let format = "kana-ascii"
    static let maxVersion = 1

    public static func load(from url: URL) throws -> KanaClip {
        guard let data = try? Data(contentsOf: url) else { throw KanaClipError.unreadable }
        return try load(data: data)
    }

    public static func load(data: Data) throws -> KanaClip {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any]
        else { throw KanaClipError.unreadable }

        guard json["format"] as? String == format else { throw KanaClipError.notKanaFile }

        let version = (json["version"] as? Int) ?? 0
        guard version >= 1, version <= maxVersion else { throw KanaClipError.unsupportedVersion(version) }

        guard let width = json["width"] as? Int, width > 0 else { throw KanaClipError.malformed("width must be a positive integer") }
        guard let height = json["height"] as? Int, height > 0 else { throw KanaClipError.malformed("height must be a positive integer") }
        let fps = max(0, (json["fps"] as? Int) ?? 0)
        let hasColor = (json["color"] as? Bool) ?? false

        guard let rawFrames = json["frames"] as? [[String: Any]], !rawFrames.isEmpty else {
            throw KanaClipError.malformed("frames must be a non-empty array")
        }

        let expectedColorBytes = width * height * 3
        var frames: [KanaFrame] = []
        frames.reserveCapacity(rawFrames.count)

        for (index, raw) in rawFrames.enumerated() {
            guard let rows = raw["rows"] as? [String] else {
                throw KanaClipError.malformed("frame \(index) has no rows")
            }
            guard rows.count == height else {
                throw KanaClipError.malformed("frame \(index) has \(rows.count) rows, expected \(height)")
            }
            // Count Characters, not bytes: the blocks and dots ramps are multi-byte.
            for (y, row) in rows.enumerated() where row.count != width {
                throw KanaClipError.malformed("frame \(index) row \(y) is \(row.count) characters, expected \(width)")
            }

            var colors: Data?
            if hasColor {
                guard let encoded = raw["colors"] as? String, let decoded = Data(base64Encoded: encoded) else {
                    throw KanaClipError.malformed("frame \(index) is missing base64 colors")
                }
                guard decoded.count == expectedColorBytes else {
                    throw KanaClipError.malformed("frame \(index) colors are \(decoded.count) bytes, expected \(expectedColorBytes)")
                }
                colors = decoded
            }
            frames.append(KanaFrame(rows: rows, colors: colors))
        }

        let requested = (json["portrait"] as? Int) ?? (frames.count - 1)
        let portrait = min(max(requested, 0), frames.count - 1)

        return KanaClip(width: width, height: height, fps: fps, hasColor: hasColor, portraitIndex: portrait, frames: frames)
    }
}
