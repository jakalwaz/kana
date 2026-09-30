import KanaCore
import Testing

@Suite struct FuzzyMatchTests {
    @Test func nonMatches() {
        #expect(FuzzyMatch.match("abc", in: "acb") == nil)
        #expect(FuzzyMatch.match("xx", in: "x") == nil)
        #expect(FuzzyMatch.match("x", in: "") == nil)
        #expect(FuzzyMatch.match("z", in: "Split Right") == nil)
    }

    @Test func emptyQueries() {
        for query in ["", " \t\n", "\u{2003}"] {
            for candidate in ["", "Split Right", "中文👩🏽‍💻"] {
                #expect(FuzzyMatch.match(query, in: candidate) == FuzzyMatch(score: 0, positions: []))
            }
        }
    }

    @Test func caseInsensitivePositions() {
        #expect(FuzzyMatch.match("sR", in: "Split Right")?.positions == [0, 6])
        #expect(FuzzyMatch.match("nE", in: "Next Split")?.positions == [0, 1])
        #expect(FuzzyMatch.match("nE", in: "New Tab")?.positions == [0, 1])
    }

    @Test func wordStartBeatsMiddle() throws {
        let boundary = try #require(FuzzyMatch.match("r", in: "a right"))
        let middle = try #require(FuzzyMatch.match("r", in: "aaright"))
        #expect(boundary.score > middle.score)
    }

    @Test func allContractBoundaries() {
        for separator in [" ", "-", "_", "/", ":", "."] {
            #expect(FuzzyMatch.match("r", in: "arr\(separator)Right")?.positions == [4])
        }
        #expect(FuzzyMatch.match("r", in: "arrRight")?.positions == [3])
    }

    @Test func consecutiveBeatsScattered() throws {
        let consecutive = try #require(FuzzyMatch.match("abc", in: "abcxx"))
        let scattered = try #require(FuzzyMatch.match("abc", in: "axbxc"))
        #expect(consecutive.score > scattered.score)
    }

    @Test func bestAlignmentUsesLaterWord() {
        #expect(FuzzyMatch.match("sr", in: "Search Right")?.positions == [0, 7])
        #expect(FuzzyMatch.match("ne", in: "Navigate Elsewhere")?.positions == [0, 9])
        #expect(FuzzyMatch.match("ab", in: "xaxxab")?.positions == [4, 5])
        #expect(FuzzyMatch.match("abc", in: "abx abc")?.positions == [4, 5, 6])
    }

    @Test func startAndLengthAndGapPenalties() throws {
        let start = try #require(FuzzyMatch.match("a", in: "a x"))
        let later = try #require(FuzzyMatch.match("a", in: "x a"))
        #expect(start.score > later.score)
        let short = try #require(FuzzyMatch.match("ab", in: "ab"))
        let long = try #require(FuzzyMatch.match("ab", in: "abxxxx"))
        #expect(short.score > long.score)
        let smallGap = try #require(FuzzyMatch.match("ab", in: "axbxx"))
        let largeGap = try #require(FuzzyMatch.match("ab", in: "axxxb"))
        #expect(smallGap.score > largeGap.score)
    }

    @Test func unicodeCharacterOffsets() {
        #expect(FuzzyMatch.match("👩🏽‍💻文", in: "Go 👩🏽‍💻 中文")?.positions == [3, 6])
        #expect(FuzzyMatch.match("é文", in: "E\u{301}中文")?.positions == [0, 2])
        // İ lowercases to multiple scalars, but remains one original Character.
        #expect(FuzzyMatch.match("İx", in: "İ x")?.positions == [0, 2])
    }

    @Test func literalWhitespaceInNonemptyQuery() {
        #expect(FuzzyMatch.match(" ab", in: "ab") == nil)
        #expect(FuzzyMatch.match("ab ", in: "ab") == nil)
        #expect(FuzzyMatch.match("a b", in: "a b")?.positions == [0, 1, 2])
    }

    @Test func tiesPreserveInputOrder() {
        let items = [(id: 3, title: "New Tab"), (id: 1, title: "NEW TAB"), (id: 2, title: "New Tab")]
        #expect(FuzzyRanker.rank(items, query: "nt", text: \.title).map(\.item.id) == [3, 1, 2])
    }

    @Test func emptyRankingPreservesEverything() {
        let titles = ["Zoom", "Split Right", "", "New Tab"]
        for query in ["", " \n"] {
            let ranked = FuzzyRanker.rank(titles, query: query, text: { $0 })
            #expect(ranked.map(\.item) == titles)
            #expect(ranked.allSatisfy { $0.match == FuzzyMatch(score: 0, positions: []) })
        }
        #expect(FuzzyRanker.rank([String](), query: "a", text: { $0 }).isEmpty)
    }

    @Test func realisticRanking() {
        let titles = ["Equalize Splits", "New Tab", "Split Right", "Split Down", "Theme: Dracula"]
        let splits = FuzzyRanker.rank(titles, query: "split", text: { $0 })
        #expect(Set(splits.prefix(2).map(\.item)) == ["Split Right", "Split Down"])
        #expect(splits.last?.item == "Equalize Splits")
        #expect(splits.allSatisfy { $0.match.positions.count == 5 })
        let themes = FuzzyRanker.rank(titles, query: "theme drac", text: { $0 })
        #expect(themes.map(\.item) == ["Theme: Dracula"])
        #expect(themes.first?.match.positions == [0, 1, 2, 3, 4, 6, 7, 8, 9, 10])
        #expect(FuzzyRanker.rank(titles, query: "zzzz", text: { $0 }).isEmpty)
    }
}
