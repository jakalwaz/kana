import Foundation
@testable import KanaSkins
import Testing

// swift-testing rather than XCTest: it ships with the Command Line Tools,
// so `swift test` works without a full Xcode.

func clipJSON(
    width: Int = 3, height: Int = 2, fps: Int = 15, color: Bool = true, portrait: Int? = nil,
    frames: [[String: Any]]? = nil, version: Int = 1, format: String = "kana-ascii"
) -> Data {
    let rgb = Data(repeating: 200, count: width * height * 3).base64EncodedString()
    // "d░f" is 3 Characters but 5 UTF-8 bytes, like the blocks ramp
    let frame: [String: Any] = color ? ["rows": ["abc", "d░f"], "colors": rgb] : ["rows": ["abc", "d░f"]]
    var json: [String: Any] = [
        "format": format, "version": version, "width": width, "height": height,
        "fps": fps, "color": color, "frames": frames ?? [frame, frame],
    ]
    if let portrait { json["portrait"] = portrait }
    return try! JSONSerialization.data(withJSONObject: json)
}

func malformedMessage(_ body: () throws -> Void) -> String? {
    do { try body() } catch let KanaClipError.malformed(message) { return message } catch { return nil }
    return nil
}

@Suite struct KanaClipLoaderTests {
    @Test func loadsGoodClipWithMultiByteRows() throws {
        let clip = try KanaClipLoader.load(data: clipJSON())
        #expect(clip.width == 3)
        #expect(clip.height == 2)
        #expect(clip.frames.count == 2)
        #expect(clip.portraitIndex == 1, "defaults to the last frame")
        #expect(abs(clip.duration - 2.0 / 15.0) < 1e-9)
        #expect(clip.portrait.color(x: 2, y: 1, width: 3)?.r == 200)
        #expect(clip.portrait.color(x: 3, y: 1, width: 3) == nil)
    }

    @Test func still() throws {
        let clip = try KanaClipLoader.load(data: clipJSON(fps: 0, color: false, frames: [["rows": ["abc", "def"]]]))
        #expect(clip.fps == 0)
        #expect(clip.duration == 0)
        #expect(!clip.hasColor)
        #expect(clip.portrait.colors == nil)
    }

    @Test func badJSON() {
        #expect(throws: KanaClipError.unreadable) { try KanaClipLoader.load(data: Data("{nope".utf8)) }
    }

    @Test func wrongFormatAndVersion() {
        #expect(throws: KanaClipError.notKanaFile) { try KanaClipLoader.load(data: clipJSON(format: "gif")) }
        #expect(throws: KanaClipError.unsupportedVersion(9)) { try KanaClipLoader.load(data: clipJSON(version: 9)) }
    }

    @Test func wrongRowWidth() {
        let data = clipJSON(color: false, frames: [["rows": ["abcd", "def"]]])
        let message = malformedMessage { _ = try KanaClipLoader.load(data: data) }
        #expect(message?.contains("row 0") == true)
    }

    @Test func wrongRowCount() {
        let data = clipJSON(color: false, frames: [["rows": ["abc"]]])
        #expect(malformedMessage { _ = try KanaClipLoader.load(data: data) } != nil)
    }

    @Test func wrongColorLength() {
        let short = Data(repeating: 1, count: 5).base64EncodedString()
        let data = clipJSON(frames: [["rows": ["abc", "def"], "colors": short]])
        let message = malformedMessage { _ = try KanaClipLoader.load(data: data) }
        #expect(message?.contains("colors") == true)
    }

    @Test func portraitClamping() throws {
        #expect(try KanaClipLoader.load(data: clipJSON(portrait: 99)).portraitIndex == 1)
        #expect(try KanaClipLoader.load(data: clipJSON(portrait: -4)).portraitIndex == 0)
    }
}

@Suite struct SkinLoaderTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kana-skins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ json: String, to folder: String) throws -> URL {
        let dir = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("skin.json"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func loadsSkinWithIntroAndFallsBack() throws {
        let dir = try write(##"{"name":"Test","accent":"#112233","portrait_opacity":2}"##, to: "test")
        try clipJSON().write(to: dir.appendingPathComponent("intro.kana"))

        let skin = try SkinLoader.load(directory: dir)
        #expect(skin.name == "Test")
        #expect(skin.accentHex == "#112233")
        #expect(skin.portraitOpacity == 1, "clamped")
        #expect(skin.intro != nil)
        #expect(skin.portrait == nil)
        #expect(skin.restingClip != nil)
    }

    @Test func badAccentFallsBackToDefault() throws {
        let dir = try write(#"{"accent":"red"}"#, to: "x")
        #expect(try SkinLoader.load(directory: dir).accentHex == SkinLoader.defaultAccent)
    }

    @Test func available() throws {
        _ = try write("{}", to: "b")
        _ = try write("{}", to: "a")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        #expect(SkinLoader.available(in: root).map(\.lastPathComponent) == ["a", "b"])
    }
}
