// Contract C2 (TASKS.md): the split layout of one tab. A pure value type,
// no AppKit, so it's unit tested in Tests/KanaCoreTests.
//
// Ported from Ghostty's macos/Sources/Features/Splits/SplitTree.swift (MIT),
// simplified to address leaves by identity instead of node paths.
//
// Coordinates are flipped (y grows downward), like SplitContainerView: the
// `first` side of a vertical split is the top one.

import CoreGraphics

/// How a split divides its space.
public enum SplitAxis: Sendable, Equatable {
    /// first | second, side by side
    case horizontal
    /// first above second
    case vertical
}

/// Where a new leaf goes, relative to the one it splits.
public enum SplitSide: Sendable, Equatable {
    case left, right, up, down
}

/// Which leaf to focus next.
public enum SplitFocus: Sendable, Equatable {
    /// Reading order (`leaves`), wrapping around.
    case previous, next
    /// The nearest leaf on that side, by frame.
    case left, right, up, down
}

/// Picks one split in the tree: from the root, `false` goes to `first`,
/// `true` to `second`. The root split's path is empty.
public struct SplitPath: Hashable, Sendable {
    public let steps: [Bool]
    public init(_ steps: [Bool] = []) { self.steps = steps }
}

public struct SplitTree<Leaf: AnyObject> {
    public indirect enum Node {
        case leaf(Leaf)
        case split(Split)
    }

    public struct Split {
        public let axis: SplitAxis
        /// The first side's share, 0.1...0.9.
        public let ratio: Double
        public let first: Node
        public let second: Node

        public init(axis: SplitAxis, ratio: Double, first: Node, second: Node) {
            self.axis = axis
            self.ratio = ratio
            self.first = first
            self.second = second
        }
    }

    public let root: Node?
    /// When set, only this leaf shows, filling the whole tab.
    public let zoomed: Leaf?

    public init() {
        self.init(root: nil, zoomed: nil)
    }
    public init(leaf: Leaf) {
        self.init(root: .leaf(leaf), zoomed: nil)
    }
    public init(root: Node?, zoomed: Leaf?) {
        self.root = root
        self.zoomed = zoomed
    }

    public var isEmpty: Bool {
        root == nil
    }

    /// Every leaf in reading order: depth-first, `first` before `second`.
    public var leaves: [Leaf] {
        root?.allLeaves ?? []
    }

    /// Identity (===), not equality.
    public func contains(_ leaf: Leaf) -> Bool {
        leaves.contains { $0 === leaf }
    }

    /// Replaces `existing` with a split holding it and `new` (ratio 0.5), with
    /// `new` on `side`. Clears the zoom. Returns self unchanged if `existing`
    /// isn't in the tree.
    public func inserting(_ new: Leaf, at existing: Leaf, side: SplitSide) -> SplitTree {
        guard let root, contains(existing) else { return self }
        let axis: SplitAxis = (side == .left || side == .right) ? .horizontal : .vertical
        let newFirst = side == .left || side == .up
        let replacement = Node.split(Split(
            axis: axis, ratio: 0.5,
            first: .leaf(newFirst ? new : existing),
            second: .leaf(newFirst ? existing : new)))
        return SplitTree(root: root.replacing(existing, with: replacement), zoomed: nil)
    }

    /// Drops the leaf; its sibling takes the parent split's place. Removing
    /// the last leaf gives an empty tree. Clears the zoom only if the zoomed
    /// leaf was removed. Returns self unchanged if the leaf isn't there.
    public func removing(_ leaf: Leaf) -> SplitTree {
        guard let root, contains(leaf) else { return self }
        return SplitTree(root: root.removing(leaf), zoomed: zoomed === leaf ? nil : zoomed)
    }

    /// Zooms the leaf, or unzooms if it's the zoomed one. No-op for a tree
    /// with fewer than two leaves or a leaf that isn't there.
    public func toggledZoom(_ leaf: Leaf) -> SplitTree {
        guard leaves.count >= 2, contains(leaf) else { return self }
        return SplitTree(root: root, zoomed: zoomed === leaf ? nil : leaf)
    }

    /// Resets ratios so leaves share space evenly along each axis, weighted
    /// by how many leaves each side holds in that axis (like Ghostty).
    public func equalized() -> SplitTree {
        SplitTree(root: root?.equalized(), zoomed: zoomed)
    }

    /// Sets one split's ratio, clamped to 0.1...0.9. Returns self unchanged
    /// if the path doesn't name a split.
    public func resizing(_ path: SplitPath, ratio: Double) -> SplitTree {
        guard let root, !ratio.isNaN else { return self }
        return SplitTree(
            root: root.resizing(path.steps[...], ratio: min(0.9, max(0.1, ratio))),
            zoomed: zoomed)
    }

    /// The leaf to focus when moving from `leaf`. previous/next wrap around.
    /// Spatial moves pick, among leaves whose frame lies entirely on that
    /// side of `leaf`'s frame, the nearest one (smallest gap along the move),
    /// then among those the one overlapping it most on the other axis, then
    /// the closest top-left corner; nil when there's none. Uses the unzoomed
    /// layout.
    public func focusTarget(from leaf: Leaf, _ direction: SplitFocus, in bounds: CGRect) -> Leaf? {
        let ordered = leaves
        guard let index = ordered.firstIndex(where: { $0 === leaf }) else { return nil }
        switch direction {
        case .previous: return ordered[(index + ordered.count - 1) % ordered.count]
        case .next: return ordered[(index + 1) % ordered.count]
        default: break
        }

        // Navigation must include hidden panes when zoomed. No divider thickness
        // is supplied for focus, so use the same layout with zero-width dividers.
        let frames = SplitTree(root: root, zoomed: nil).layout(in: bounds, divider: 0).frames
        guard let reference = frames.first(where: { $0.leaf === leaf })?.frame else { return nil }
        var best: Leaf?
        var bestGap = CGFloat.infinity
        var bestOverlap: CGFloat = -1
        var bestDistance = CGFloat.infinity
        for candidate in frames where candidate.leaf !== leaf {
            let frame = candidate.frame
            let onSide: Bool
            let overlap: CGFloat
            let gap: CGFloat
            switch direction {
            case .left, .right:
                onSide = direction == .left ? frame.maxX <= reference.minX : frame.minX >= reference.maxX
                gap = direction == .left ? reference.minX - frame.maxX : frame.minX - reference.maxX
                overlap = max(0, min(frame.maxY, reference.maxY) - max(frame.minY, reference.minY))
            case .up, .down:
                onSide = direction == .up ? frame.maxY <= reference.minY : frame.minY >= reference.maxY
                gap = direction == .up ? reference.minY - frame.maxY : frame.minY - reference.maxY
                overlap = max(0, min(frame.maxX, reference.maxX) - max(frame.minX, reference.minX))
            case .previous, .next:
                continue
            }
            guard onSide else { continue }
            // Ghostty measures distance between top-left corners. Squaring it
            // preserves the ordering; exact ties retain reading order.
            let dx = frame.minX - reference.minX
            let dy = frame.minY - reference.minY
            let distance = dx * dx + dy * dy
            if gap < bestGap || (gap == bestGap &&
                (overlap > bestOverlap || (overlap == bestOverlap && distance < bestDistance))) {
                best = candidate.leaf
                bestGap = gap
                bestOverlap = overlap
                bestDistance = distance
            }
        }
        return best
    }

    /// Frames for every leaf and divider. `divider` is the divider's
    /// thickness: a split of width W gives its first side
    /// round((W - divider) * ratio) and the second the rest. Zoomed trees
    /// return just the zoomed leaf at `bounds`, and no dividers.
    public func layout(in bounds: CGRect, divider: CGFloat) -> SplitLayout<Leaf> {
        if let zoomed {
            return SplitLayout(frames: [(zoomed, bounds)], dividers: [])
        }
        var frames: [(leaf: Leaf, frame: CGRect)] = []
        var dividers: [SplitDivider] = []
        root?.appendLayout(in: bounds, divider: divider, path: [], frames: &frames, dividers: &dividers)
        return SplitLayout(frames: frames, dividers: dividers)
    }
}

public struct SplitLayout<Leaf: AnyObject> {
    /// In `leaves` order.
    public let frames: [(leaf: Leaf, frame: CGRect)]
    public let dividers: [SplitDivider]

    public init(frames: [(leaf: Leaf, frame: CGRect)], dividers: [SplitDivider]) {
        self.frames = frames
        self.dividers = dividers
    }
}

public struct SplitDivider: Sendable, Equatable {
    /// The split this divider belongs to, for `resizing`.
    public let path: SplitPath
    public let axis: SplitAxis
    /// The divider itself.
    public let rect: CGRect
    /// The whole split's rect, to turn a drag position into a ratio.
    public let span: CGRect

    public init(path: SplitPath, axis: SplitAxis, rect: CGRect, span: CGRect) {
        self.path = path
        self.axis = axis
        self.rect = rect
        self.span = span
    }
}


private extension SplitTree.Node {
    var allLeaves: [Leaf] {
        switch self {
        case .leaf(let leaf): return [leaf]
        case .split(let split): return split.first.allLeaves + split.second.allLeaves
        }
    }

    func replacing(_ target: Leaf, with replacement: Self) -> Self {
        switch self {
        case .leaf(let leaf): return leaf === target ? replacement : self
        case .split(let split):
            return .split(.init(axis: split.axis, ratio: split.ratio,
                                first: split.first.replacing(target, with: replacement),
                                second: split.second.replacing(target, with: replacement)))
        }
    }

    func removing(_ target: Leaf) -> Self? {
        switch self {
        case .leaf(let leaf): return leaf === target ? nil : self
        case .split(let split):
            let first = split.first.removing(target)
            let second = split.second.removing(target)
            guard let first else { return second }
            guard let second else { return first }
            return .split(.init(axis: split.axis, ratio: split.ratio, first: first, second: second))
        }
    }

    // A perpendicular split occupies one unit along the requested axis,
    // regardless of how many panes it contains (Ghostty's weightForDirection).
    func weight(along axis: SplitAxis) -> Int {
        guard case .split(let split) = self, split.axis == axis else { return 1 }
        return split.first.weight(along: axis) + split.second.weight(along: axis)
    }

    func equalized() -> Self {
        guard case .split(let split) = self else { return self }
        let firstWeight = split.first.weight(along: split.axis)
        let total = firstWeight + split.second.weight(along: split.axis)
        let ratio = min(0.9, max(0.1, Double(firstWeight) / Double(total)))
        return .split(.init(axis: split.axis, ratio: ratio,
                            first: split.first.equalized(), second: split.second.equalized()))
    }

    func resizing(_ steps: ArraySlice<Bool>, ratio: Double) -> Self {
        guard case .split(let split) = self else { return self }
        guard let second = steps.first else {
            return .split(.init(axis: split.axis, ratio: ratio, first: split.first, second: split.second))
        }
        return .split(.init(
            axis: split.axis, ratio: split.ratio,
            first: second ? split.first : split.first.resizing(steps.dropFirst(), ratio: ratio),
            second: second ? split.second.resizing(steps.dropFirst(), ratio: ratio) : split.second))
    }

    func appendLayout(
        in bounds: CGRect, divider: CGFloat, path: [Bool],
        frames: inout [(leaf: Leaf, frame: CGRect)], dividers: inout [SplitDivider]
    ) {
        switch self {
        case .leaf(let leaf):
            frames.append((leaf, bounds))
        case .split(let split):
            var first = bounds
            var second = bounds
            var separator = bounds
            switch split.axis {
            case .horizontal:
                let extent = max(0, ((bounds.width - divider) * CGFloat(split.ratio)).rounded())
                first.size.width = extent
                separator.origin.x = bounds.minX + extent
                separator.size.width = divider
                second.origin.x = separator.maxX
                second.size.width = max(0, bounds.width - extent - divider)
            case .vertical:
                let extent = max(0, ((bounds.height - divider) * CGFloat(split.ratio)).rounded())
                first.size.height = extent
                separator.origin.y = bounds.minY + extent
                separator.size.height = divider
                second.origin.y = separator.maxY
                second.size.height = max(0, bounds.height - extent - divider)
            }
            dividers.append(.init(path: SplitPath(path), axis: split.axis, rect: separator, span: bounds))
            split.first.appendLayout(in: first, divider: divider, path: path + [false],
                                     frames: &frames, dividers: &dividers)
            split.second.appendLayout(in: second, divider: divider, path: path + [true],
                                      frames: &frames, dividers: &dividers)
        }
    }
}
