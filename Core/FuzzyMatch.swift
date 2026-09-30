// Contract C4 (TASKS.md), part 1: fuzzy matching for the command palette.
// Pure Swift, unit tested in Tests/KanaCoreTests.

/// How well a query matches one candidate, like VS Code's or Ghostty's
/// palette: every query character must appear in order, case-insensitively.
public struct FuzzyMatch: Sendable, Equatable {
    /// Higher is better. Rewards consecutive runs, matches at word starts
    /// (after a space, `-`, `_`, `/`, `:` or `.`, or a lower-to-upper case
    /// change) and at the very start; penalises gaps and long candidates.
    public let score: Int
    /// Offsets (in Characters) of the matched characters in the candidate,
    /// ascending, one per query character. For highlighting.
    public let positions: [Int]

    public init(score: Int, positions: [Int]) {
        self.score = score
        self.positions = positions
    }

    /// nil when the query's characters don't all appear in order. An empty
    /// (or all-whitespace) query matches everything with score 0 and no
    /// positions. Picks the best-scoring alignment, not just the first.
    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? { fatalError("T1.8") }
}

public enum FuzzyRanker {
    /// The items that match, best first. Equal scores keep the input order,
    /// so an empty query returns everything as given.
    public static func rank<T>(_ items: [T], query: String, text: (T) -> String) -> [(item: T, match: FuzzyMatch)] {
        fatalError("T1.8")
    }
}
