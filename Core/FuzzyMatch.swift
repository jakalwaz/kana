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
    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        guard !query.allSatisfy(\.isWhitespace) else {
            return FuzzyMatch(score: 0, positions: [])
        }
        let needle = query.map { $0.lowercased() }
        let characters = Array(candidate)
        let count = characters.count
        guard needle.count <= count else { return nil }
        // Fold each Character separately so case expansion never shifts offsets.
        let folded = characters.map { $0.lowercased() }
        let boundaries = characters.indices.map { index in
            index == 0 || " -_/:.".contains(characters[index - 1])
                || (characters[index - 1].isLowercase && characters[index].isUppercase)
        }
        var previous = [Int?](repeating: nil, count: count)
        var parents = Array(repeating: [Int](repeating: -1, count: count), count: needle.count)

        // Each cell is the best alignment ending at this candidate Character.
        // A running maximum of score + offset handles all nonadjacent parents
        // in O(1); adjacency is scored separately for the consecutive bonus.
        for queryIndex in needle.indices {
            var current = [Int?](repeating: nil, count: count)
            var bestGap: (score: Int, index: Int)?
            for index in characters.indices {
                if index >= 2, let score = previous[index - 2] {
                    let adjusted = score + index - 2
                    if bestGap == nil || adjusted > bestGap!.score {
                        bestGap = (adjusted, index - 2)
                    }
                }
                guard needle[queryIndex] == folded[index] else { continue }
                let reward = 10 + (boundaries[index] ? 16 : 0)
                if queryIndex == 0 {
                    current[index] = reward + (index == 0 ? 8 : 0) - index - count
                    continue
                }
                if let bestGap {
                    current[index] = bestGap.score - index + 1 + reward
                    parents[queryIndex][index] = bestGap.index
                }
                if index > 0, let adjacent = previous[index - 1] {
                    let score = adjacent + 12 + reward
                    if current[index] == nil || score > current[index]! {
                        current[index] = score
                        parents[queryIndex][index] = index - 1
                    }
                }
            }
            previous = current
        }
        var best: (score: Int, index: Int)?
        for (index, score) in previous.enumerated() {
            if let score, best == nil || score > best!.score {
                best = (score, index)
            }
        }
        guard let best else { return nil }
        var positions = [Int](repeating: 0, count: needle.count)
        var index = best.index
        for queryIndex in needle.indices.reversed() {
            positions[queryIndex] = index
            index = parents[queryIndex][index]
        }
        return FuzzyMatch(score: best.score, positions: positions)
    }
}

public enum FuzzyRanker {
    /// The items that match, best first. Equal scores keep the input order,
    /// so an empty query returns everything as given.
    public static func rank<T>(_ items: [T], query: String, text: (T) -> String) -> [(item: T, match: FuzzyMatch)] {
        items.enumerated().compactMap { index, item in
            FuzzyMatch.match(query, in: text(item)).map { (index: index, item: item, match: $0) }
        }.sorted {
            if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
            return $0.index < $1.index
        }.map { (item: $0.item, match: $0.match) }
    }
}
