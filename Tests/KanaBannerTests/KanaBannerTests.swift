import Foundation
@testable import KanaBanner
import KanaSkins
import Testing

func testClip(width: Int = 180, height: Int = 51, frames: Int = 3) -> KanaClip {
    let row = String(repeating: "@", count: width / 2) + String(repeating: " ", count: width - width / 2)
    let colors = Data(repeating: 200, count: width * height * 3)
    let frame = KanaFrame(rows: Array(repeating: row, count: height), colors: colors)
    return KanaClip(width: width, height: height, fps: 30, hasColor: true, portraitIndex: frames - 1,
                    frames: Array(repeating: frame, count: frames))
}

func options(columns: Int, rows: Int, clip: KanaClip? = testClip()) -> Banner.Options {
    .init(columns: columns, rows: rows, accent: RGB(0xE0, 0x26, 0x2F), workingDirectory: "/tmp", skinName: "Akira", clip: clip)
}

@Suite struct AnsiTests {
    @Test func widthIgnoresEscapesAndCountsWideCharacters() {
        #expect(Ansi.visibleWidth(Ansi.paint("abc", .grey)) == 3)
        #expect(Ansi.visibleWidth("カナ") == 4)
        #expect(Ansi.visibleWidth("╭─⌘✦█") == 5)
    }

    @Test func fitPadsAndCuts() {
        #expect(Ansi.visibleWidth(Ansi.fit("ab", 6, align: .center)) == 6)
        #expect(Ansi.visibleWidth(Ansi.fit(Ansi.paint("abcdefgh", .grey), 5)) == 5)
    }
}

@Suite struct BannerTests {
    /// A clip with something at both edges, so trimming keeps its full width.
    func wideClip() -> KanaClip {
        let row = "@" + String(repeating: " ", count: 178) + "@"
        let frame = KanaFrame(rows: Array(repeating: row, count: 51), colors: Data(repeating: 90, count: 180 * 51 * 3))
        return KanaClip(width: 180, height: 51, fps: 30, hasColor: true, portraitIndex: 0, frames: [frame, frame])
    }

    @Test(arguments: [(50, 30), (80, 36), (120, 36), (120, 60), (200, 60), (90, 24)])
    func everyLineIsTheFullWidth(size: (Int, Int)) {
        let b = Banner(options(columns: size.0, rows: size.1, clip: wideClip()))
        for line in b.head + b.artLines(frame: 0) + b.panels + [b.bottom] {
            #expect(Ansi.visibleWidth(line) == max(40, size.0))
        }
    }

    @Test(arguments: [(80, 36), (120, 36), (120, 60), (200, 60), (160, 30)])
    func wholePictureNeverCropped(size: (Int, Int)) throws {
        let b = Banner(options(columns: size.0, rows: size.1, clip: wideClip()))
        let clip = try #require(b.clip)
        let expectedHeight = Double(clip.width) * 51 / 180
        #expect(abs(Double(clip.height) - expectedHeight) <= 1)
        #expect(clip.width <= size.0 - 4)
    }

    @Test(arguments: [(80, 36), (120, 36), (200, 40), (120, 30), (140, 46)])
    func finishedScreenFitsWithThePromptSoKanaStaysInView(size: (Int, Int)) {
        let b = Banner(options(columns: size.0, rows: size.1, clip: wideClip()))
        #expect(b.height + 2 <= size.1)
    }

    @Test func tallWindowsGetTheFullWidth() {
        let b = Banner(options(columns: 124, rows: 90, clip: wideClip()))
        #expect(b.clip?.width == 120)
        #expect(b.artHeight == 34) // 120 * 51 / 180
    }

    @Test func emptyRowsAboveTheRestingFrameAreTrimmed() throws {
        // resting frame: 10 blank rows, then content
        let blank = String(repeating: " ", count: 180)
        let full = "@" + String(repeating: " ", count: 178) + "@"
        let rest = KanaFrame(rows: Array(repeating: blank, count: 10) + Array(repeating: full, count: 41), colors: nil)
        let busy = KanaFrame(rows: Array(repeating: full, count: 51), colors: nil)
        let clip = KanaClip(width: 180, height: 51, fps: 30, hasColor: false, portraitIndex: 1, frames: [busy, rest])
        let b = Banner(options(columns: 124, rows: 90, clip: clip))
        let scaled = try #require(b.clip)
        #expect(scaled.portrait.rows[0].contains("@"))
    }

    @Test func plannedWidthMatchesTheLayout() {
        let planned = Banner.plannedArtWidth(columns: 120, rows: 36, probe: wideClip())
        let b = Banner(options(columns: 120, rows: 36, clip: wideClip()))
        #expect(planned == b.clip?.width)
    }

    @Test(arguments: [12, 20])
    func artFitsOnScreenWhileItPlays(rows: Int) {
        let b = Banner(options(columns: 200, rows: rows, clip: wideClip()))
        #expect(b.artHeight + 2 <= rows)
    }

    @Test func noClipMeansNoArt() {
        let b = Banner(options(columns: 120, rows: 40, clip: nil))
        #expect(b.artHeight == 0)
        #expect(!b.panels.isEmpty)
    }

    @Test func mentionsTheKeysButNotTheOldSubtitle() {
        let b = Banner(options(columns: 120, rows: 50))
        let text = (b.head + b.panels + [b.bottom]).joined()
        #expect(text.contains("new tab"))
        #expect(text.contains("Suggestions"))
        #expect(!text.contains("a terminal built on"))
    }
}

@Suite struct ResamplerTests {
    @Test func shrinksToTheRequestedGrid() {
        let small = AsciiResampler.resample(testClip(), width: 60, height: 17)
        #expect(small.width == 60)
        #expect(small.height == 17)
        #expect(small.frames.count == 3)
        #expect(small.frames[0].rows.allSatisfy { $0.count == 60 })
        #expect(small.frames[0].colors?.count == 60 * 17 * 3)
        // left half was dense, right half empty
        let row = Array(small.frames[0].rows[0])
        #expect(row[5] != " ")
        #expect(row[55] == " ")
        #expect(small.frames[0].color(x: 5, y: 0, width: 60)?.r == 200)
    }

    @Test func sameSizeIsUntouched() {
        let clip = testClip(width: 40, height: 10)
        #expect(AsciiResampler.resample(clip, width: 40, height: 10).frames[0].rows == clip.frames[0].rows)
    }
}
