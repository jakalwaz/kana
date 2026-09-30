import CoreGraphics
import KanaCore
import Testing

private final class Leaf {}
private typealias Tree = SplitTree<Leaf>

private func split(_ node: Tree.Node?) throws -> Tree.Split {
    let node = try #require(node)
    guard case .split(let value) = node else {
        throw TestError.expectedSplit
    }
    return value
}

private enum TestError: Error { case expectedSplit }

private func expectLeaves(_ tree: Tree, _ expected: [Leaf]) {
    #expect(tree.leaves.map(ObjectIdentifier.init) == expected.map(ObjectIdentifier.init))
}

private func grid() -> (tree: Tree, a: Leaf, b: Leaf, c: Leaf, d: Leaf) {
    let a = Leaf(), b = Leaf(), c = Leaf(), d = Leaf()
    // a | b
    // c | d
    let tree = Tree(leaf: a).inserting(b, at: a, side: .right)
        .inserting(c, at: a, side: .down).inserting(d, at: b, side: .down)
    return (tree, a, b, c, d)
}

@Suite struct SplitTreeTests {
    @Test func emptyTree() {
        let tree = Tree(), leaf = Leaf()
        #expect(tree.isEmpty)
        #expect(tree.root == nil)
        #expect(tree.zoomed == nil)
        #expect(tree.leaves.isEmpty)
        #expect(!tree.contains(leaf))
        #expect(tree.inserting(Leaf(), at: leaf, side: .right).isEmpty)
        #expect(tree.removing(leaf).isEmpty)
        #expect(tree.toggledZoom(leaf).zoomed == nil)
        #expect(tree.equalized().isEmpty)
        #expect(tree.resizing(SplitPath(), ratio: 0.8).isEmpty)
        for direction: SplitFocus in [.previous, .next, .left, .right, .up, .down] {
            #expect(tree.focusTarget(from: leaf, direction, in: .zero) == nil)
        }
        let layout = tree.layout(in: CGRect(x: 1, y: 2, width: 100, height: 80), divider: 1)
        #expect(layout.frames.isEmpty)
        #expect(layout.dividers.isEmpty)
    }

    @Test func singleLeafAndIdentity() {
        let leaf = Leaf(), other = Leaf(), tree = Tree(leaf: leaf)
        #expect(!tree.isEmpty)
        expectLeaves(tree, [leaf])
        #expect(tree.contains(leaf))
        #expect(!tree.contains(other))
        #expect(tree.zoomed == nil)
        #expect(tree.toggledZoom(leaf).zoomed == nil)
        expectLeaves(tree.equalized(), [leaf])
        expectLeaves(tree.resizing(SplitPath(), ratio: 0.2), [leaf])
        let bounds = CGRect(x: 7, y: 13, width: 101, height: 87)
        let layout = tree.layout(in: bounds, divider: 1)
        #expect(layout.frames.count == 1)
        #expect(layout.frames.first?.leaf === leaf)
        #expect(layout.frames.first?.frame == bounds)
        #expect(layout.dividers.isEmpty)
        #expect(tree.focusTarget(from: leaf, .previous, in: bounds) === leaf)
        #expect(tree.focusTarget(from: leaf, .next, in: bounds) === leaf)
        for direction: SplitFocus in [.left, .right, .up, .down] {
            #expect(tree.focusTarget(from: leaf, direction, in: bounds) == nil)
        }
    }

    @Test func explicitRootAndZoomInitializer() {
        let a = Leaf(), b = Leaf()
        let root = Tree.Node.split(.init(axis: .vertical, ratio: 0.3, first: .leaf(a), second: .leaf(b)))
        let tree = Tree(root: root, zoomed: b)
        expectLeaves(tree, [a, b])
        #expect(tree.zoomed === b)
        let layout = tree.layout(in: .zero, divider: 1)
        #expect(layout.frames.first?.leaf === b)
        #expect(layout.dividers.isEmpty)
    }

    @Test func insertionOnEverySide() throws {
        for side: SplitSide in [.left, .right, .up, .down] {
            let a = Leaf(), b = Leaf(), original = Tree(leaf: a)
            let tree = original.inserting(b, at: a, side: side)
            let root = try split(tree.root)
            let newFirst = side == .left || side == .up
            #expect(root.axis == ((side == .left || side == .right) ? .horizontal : .vertical))
            #expect(root.ratio == 0.5)
            expectLeaves(tree, newFirst ? [b, a] : [a, b])
            expectLeaves(original, [a])
        }
    }

    @Test func nestedInsertionAndReadingOrder() throws {
        let g = grid()
        expectLeaves(g.tree, [g.a, g.c, g.b, g.d])
        let root = try split(g.tree.root)
        #expect(root.axis == .horizontal)
        #expect(try split(root.first).axis == .vertical)
        #expect(try split(root.second).axis == .vertical)
    }

    @Test func insertionClearsZoomOnlyWhenTargetExists() {
        let g = grid(), extra = Leaf(), missing = Leaf()
        let zoomed = g.tree.toggledZoom(g.a)
        let inserted = zoomed.inserting(extra, at: g.d, side: .left)
        #expect(inserted.zoomed == nil)
        expectLeaves(inserted, [g.a, g.c, g.b, extra, g.d])
        let unchanged = zoomed.inserting(extra, at: missing, side: .up)
        #expect(unchanged.zoomed === g.a)
        expectLeaves(unchanged, zoomed.leaves)
    }

    @Test func removingNestedLeavesPromotesSibling() throws {
        let g = grid()
        for target in [g.a, g.c, g.b, g.d] {
            let result = g.tree.removing(target)
            expectLeaves(result, g.tree.leaves.filter { $0 !== target })
            let root = try split(result.root)
            #expect(root.axis == .horizontal)
            #expect(root.ratio == 0.5)
            #expect(result.layout(in: CGRect(x: 0, y: 0, width: 101, height: 101), divider: 1).dividers.count == 2)
        }
        let remaining = g.tree.removing(g.a).removing(g.c)
        expectLeaves(remaining, [g.b, g.d])
        #expect(try split(remaining.root).axis == .vertical)
        expectLeaves(g.tree, [g.a, g.c, g.b, g.d])
    }

    @Test func removingLastLeafAndMissingLeaf() {
        let a = Leaf(), b = Leaf()
        let single = Tree(leaf: a)
        #expect(single.removing(a).isEmpty)
        #expect(single.removing(a).zoomed == nil)
        expectLeaves(single.removing(b), [a])
        let tree = single.inserting(b, at: a, side: .down).toggledZoom(a)
        let unchanged = tree.removing(Leaf())
        expectLeaves(unchanged, [a, b])
        #expect(unchanged.zoomed === a)
    }

    @Test func zoomSurvivesOtherRemovalAndClearsOnOwnRemoval() {
        let g = grid(), zoomed = g.tree.toggledZoom(g.a)
        #expect(zoomed.removing(g.d).zoomed === g.a)
        #expect(zoomed.removing(g.a).zoomed == nil)
        let single = zoomed.removing(g.b).removing(g.c).removing(g.d)
        expectLeaves(single, [g.a])
        #expect(single.zoomed === g.a)
        #expect(single.removing(g.a).zoomed == nil)
        #expect(single.removing(g.a).isEmpty)
    }

    @Test func togglingAndSwitchingZoom() {
        let g = grid(), zoomed = g.tree.toggledZoom(g.a)
        #expect(zoomed.zoomed === g.a)
        #expect(zoomed.toggledZoom(g.a).zoomed == nil)
        #expect(zoomed.toggledZoom(g.b).zoomed === g.b)
        #expect(zoomed.toggledZoom(Leaf()).zoomed === g.a)
        let bounds = CGRect(x: 5, y: 10, width: 203, height: 117)
        let layout = zoomed.layout(in: bounds, divider: 1)
        #expect(layout.frames.count == 1)
        #expect(layout.frames.first?.leaf === g.a)
        #expect(layout.frames.first?.frame == bounds)
        #expect(layout.dividers.isEmpty)
        #expect(zoomed.toggledZoom(g.a).layout(in: bounds, divider: 1).frames.count == 4)
    }

    @Test func equalizesThreeWayRowsAndColumns() throws {
        for side: SplitSide in [.left, .right, .up, .down] {
            let a = Leaf(), b = Leaf(), c = Leaf()
            let tree = Tree(leaf: a).inserting(b, at: a, side: side).inserting(c, at: b, side: side)
            let equalized = tree.equalized()
            let root = try split(equalized.root)
            let firstIsPair = side == .left || side == .up
            #expect(root.ratio == (firstIsPair ? 2.0 / 3.0 : 1.0 / 3.0))
            #expect(try split(firstIsPair ? root.first : root.second).ratio == 0.5)
            #expect(try split(tree.root).ratio == 0.5)
        }
    }

    @Test func equalizesMixedAxesAndPreservesZoom() throws {
        let a = Leaf(), b = Leaf(), c = Leaf(), d = Leaf(), e = Leaf()
        // Root's left side has three leaves under a perpendicular split (weight 1).
        // Its right side has two horizontal leaves (weight 2).
        let tree = Tree(leaf: a).inserting(b, at: a, side: .right)
            .inserting(c, at: a, side: .down).inserting(d, at: c, side: .right)
            .inserting(e, at: b, side: .right).resizing(SplitPath([false]), ratio: 0.8)
            .toggledZoom(d)
        let equalized = tree.equalized(), root = try split(equalized.root)
        #expect(root.ratio == 1.0 / 3.0)
        #expect(try split(root.first).ratio == 0.5)
        #expect(try split(root.second).ratio == 0.5)
        #expect(try split(try split(root.first).second).ratio == 0.5)
        #expect(equalized.zoomed === d)
        expectLeaves(equalized, [a, c, d, b, e])
    }

    @Test func resizeClampsAndPreservesOtherSplitsAndZoom() throws {
        let g = grid(), tree = g.tree.toggledZoom(g.c)
        for (input, expected) in [(-1.0, 0.1), (0.0, 0.1), (0.1, 0.1), (0.34, 0.34),
                                  (0.9, 0.9), (2.0, 0.9), (-Double.infinity, 0.1), (Double.infinity, 0.9)] {
            #expect(try split(tree.resizing(SplitPath(), ratio: input).root).ratio == expected)
        }
        let resized = tree.resizing(SplitPath([true]), ratio: 0.7)
        let root = try split(resized.root)
        #expect(root.ratio == 0.5)
        #expect(try split(root.first).ratio == 0.5)
        #expect(try split(root.second).ratio == 0.7)
        #expect(resized.zoomed === g.c)
        expectLeaves(resized, tree.leaves)
        #expect(try split(try split(tree.root).second).ratio == 0.5)
    }

    @Test func badResizePathsAreNoOps() {
        let g = grid(), bounds = CGRect(x: 3, y: 4, width: 201, height: 151)
        let original = g.tree.layout(in: bounds, divider: 1)
        for path in [SplitPath([false, false]), SplitPath([true, true]), SplitPath([true, false, true])] {
            let result = g.tree.resizing(path, ratio: 0.8).layout(in: bounds, divider: 1)
            #expect(result.frames.map(\.frame) == original.frames.map(\.frame))
            #expect(result.dividers == original.dividers)
        }
        #expect(g.tree.resizing(SplitPath(), ratio: .nan).layout(in: bounds, divider: 1).dividers == original.dividers)
    }

    @Test func layoutHasExactFramesAndDividerMetadata() {
        let g = grid(), bounds = CGRect(x: 7, y: 11, width: 102, height: 82)
        let layout = g.tree.layout(in: bounds, divider: 1)
        #expect(layout.frames.map { ObjectIdentifier($0.leaf) } == [g.a, g.c, g.b, g.d].map(ObjectIdentifier.init))
        #expect(layout.frames.map(\.frame) == [
            CGRect(x: 7, y: 11, width: 51, height: 41), CGRect(x: 7, y: 53, width: 51, height: 40),
            CGRect(x: 59, y: 11, width: 50, height: 41), CGRect(x: 59, y: 53, width: 50, height: 40)])
        #expect(layout.dividers == [
            SplitDivider(path: SplitPath(), axis: .horizontal,
                         rect: CGRect(x: 58, y: 11, width: 1, height: 82), span: bounds),
            SplitDivider(path: SplitPath([false]), axis: .vertical,
                         rect: CGRect(x: 7, y: 52, width: 51, height: 1),
                         span: CGRect(x: 7, y: 11, width: 51, height: 82)),
            SplitDivider(path: SplitPath([true]), axis: .vertical,
                         rect: CGRect(x: 59, y: 52, width: 50, height: 1),
                         span: CGRect(x: 59, y: 11, width: 50, height: 82))])
    }

    @Test func nestedLayoutTilesBoundsWithoutGapsOrOverlaps() {
        let g = grid()
        let tree = g.tree.inserting(Leaf(), at: g.d, side: .left)
            .resizing(SplitPath(), ratio: 0.37).resizing(SplitPath([false]), ratio: 0.63)
        for width in [100, 101, 102, 307] {
            let bounds = CGRect(x: -13, y: 17, width: width, height: 203)
            let layout = tree.layout(in: bounds, divider: 1)
            let rects = layout.frames.map(\.frame) + layout.dividers.map(\.rect)
            #expect(rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height } == bounds.width * bounds.height)
            for (i, rect) in rects.enumerated() {
                #expect(bounds.contains(rect))
                for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
                    #expect(edge == edge.rounded())
                }
                for other in rects.dropFirst(i + 1) {
                    let intersection = rect.intersection(other)
                    #expect(intersection.isNull || intersection.isEmpty)
                }
            }
        }
    }

    @Test func dividerPathsAndSpansMapDragsToResizing() throws {
        let g = grid(), bounds = CGRect(x: 20, y: 30, width: 201, height: 101)
        for divider in g.tree.layout(in: bounds, divider: 1).dividers {
            let horizontal = divider.axis == .horizontal
            let origin = horizontal ? divider.span.minX : divider.span.minY
            let available = (horizontal ? divider.span.width : divider.span.height) - 1
            let dragPosition = origin + available * 0.7
            let ratio = Double((dragPosition - origin) / available)
            let resized = g.tree.resizing(divider.path, ratio: ratio).layout(in: bounds, divider: 1)
            let moved = try #require(resized.dividers.first { $0.path == divider.path })
            #expect(moved.span == divider.span)
            #expect((horizontal ? moved.rect.minX : moved.rect.minY) == dragPosition)
        }
    }

    @Test func spatialFocusInEveryGridDirectionIncludingEdges() {
        let g = grid(), bounds = CGRect(x: 7, y: 11, width: 202, height: 202)
        let rows: [(Leaf, Leaf?, Leaf?, Leaf?, Leaf?)] = [
            (g.a, nil, g.b, nil, g.c), (g.b, g.a, nil, nil, g.d),
            (g.c, nil, g.d, g.a, nil), (g.d, g.c, nil, g.b, nil)]
        for (source, left, right, up, down) in rows {
            for (direction, expected): (SplitFocus, Leaf?) in [(.left, left), (.right, right), (.up, up), (.down, down)] {
                #expect(g.tree.focusTarget(from: source, direction, in: bounds) === expected)
                #expect(g.tree.toggledZoom(g.a).focusTarget(from: source, direction, in: bounds) === expected)
            }
        }
    }

    @Test func focusPrefersNearestGapThenOverlapThenCorner() {
        // Exercise the same geometry horizontally and vertically.
        for (forward, backward, across): (SplitSide, SplitFocus, SplitSide) in [
            (.right, .left, .down), (.down, .up, .right)
        ] {
            let a = Leaf(), bTop = Leaf(), bBottom = Leaf(), c = Leaf(), cBottom = Leaf()
            let tree = Tree(leaf: a).inserting(bTop, at: a, side: forward)
                .inserting(c, at: bTop, side: forward).inserting(bBottom, at: bTop, side: across)
                .equalized()
            let bounds = CGRect(x: 7, y: 11, width: 300, height: 300)
            let move: SplitFocus = forward == .right ? .right : .down
            // C has more overlap, but both halves of B have a smaller gap.
            // Equal overlap between B's halves is resolved by the top-left corner.
            #expect(tree.focusTarget(from: a, move, in: bounds) === bTop)
            let splitC = tree.inserting(cBottom, at: c, side: across)
                .resizing(SplitPath([true, true]), ratio: 0.2)
            // C-bottom overlaps B-bottom most, although B-top's corner is closer.
            #expect(splitC.focusTarget(from: cBottom, backward, in: bounds) === bBottom)
            #expect(splitC.focusTarget(from: c, backward, in: bounds) === bTop)
        }
    }

    @Test func layoutClampsExtentsWhenBoundsAreSmallerThanDivider() {
        let g = grid()
        for size: CGFloat in [0, 0.5, 1] {
            let layout = g.tree.layout(in: CGRect(x: 7, y: 11, width: size, height: size), divider: 2)
            for entry in layout.frames {
                #expect(entry.frame.size.width == 0)
                #expect(entry.frame.size.height == 0)
            }
        }
    }

    @Test func focusBreaksEqualOverlapByNearestDistance() {
        let a = Leaf(), b = Leaf(), c = Leaf()
        let tree = Tree(leaf: a).inserting(c, at: a, side: .right).inserting(b, at: a, side: .right)
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        #expect(tree.focusTarget(from: a, .right, in: bounds) === b)
        #expect(tree.focusTarget(from: c, .left, in: bounds) === b)
    }

    @Test func readingOrderWrapsAndMissingFocusReturnsNil() {
        let g = grid(), ordered = [g.a, g.c, g.b, g.d]
        let tree = g.tree.toggledZoom(g.a)
        for (index, leaf) in ordered.enumerated() {
            #expect(tree.focusTarget(from: leaf, .next, in: .zero) === ordered[(index + 1) % 4])
            #expect(tree.focusTarget(from: leaf, .previous, in: .zero) === ordered[(index + 3) % 4])
        }
        for direction: SplitFocus in [.previous, .next, .left, .right, .up, .down] {
            #expect(tree.focusTarget(from: Leaf(), direction, in: .zero) == nil)
        }
    }
}
