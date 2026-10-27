import Foundation

/// How to order two values. Combine with `<>` to break ties: the right side only decides when the left finds them the same.
///
///     people.sorted(by: .by(\.lastName) <> .by(\.firstName) <> .by(\.age).reversed)
///
/// Named `Ordering` rather than `Comparator` because Foundation already has a `Comparator` typealias.
public struct Ordering<T> {
    public let compare: (T, T) -> ComparisonResult

    public init(_ compare: @escaping (T, T) -> ComparisonResult) {
        self.compare = compare
    }

    /// Whether `lhs` comes strictly before `rhs`, the shape `sorted(by:)` and friends expect
    public func areInIncreasingOrder(_ lhs: T, _ rhs: T) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    public var reversed: Ordering<T> {
        Ordering { compare($1, $0) }
    }
}

public extension Ordering where T: Comparable {
    static var natural: Ordering<T> {
        Ordering { lhs, rhs in
            lhs < rhs ? .orderedAscending : rhs < lhs ? .orderedDescending : .orderedSame
        }
    }
}

public extension Ordering {
    /// Orders by a property, `.by(\.age)`, or anything computed from the value
    static func by<V: Comparable>(_ transform: @escaping (T) -> V) -> Ordering<T> {
        Ordering<V>.natural.contramap(transform)
    }

    /// Orders by a property using its own ordering, `.by(\.nickname, .nilsLast(.natural))`
    static func by<V>(_ transform: @escaping (T) -> V, _ ordering: Ordering<V>) -> Ordering<T> {
        ordering.contramap(transform)
    }
}

public extension Ordering {
    /// Orders optionals with `ordering`, putting `nil` before every value
    static func nilsFirst<Wrapped>(_ ordering: Ordering<Wrapped>) -> Ordering<T> where T == Wrapped? {
        Ordering { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedAscending
            case (_, nil): return .orderedDescending
            case let (lhs?, rhs?): return ordering.compare(lhs, rhs)
            }
        }
    }

    /// Orders optionals with `ordering`, putting `nil` after every value
    static func nilsLast<Wrapped>(_ ordering: Ordering<Wrapped>) -> Ordering<T> where T == Wrapped? {
        nilsFirst(ordering.reversed).reversed
    }
}

extension Ordering: Semigroup {
    public static func <> (lhs: Ordering<T>, rhs: Ordering<T>) -> Ordering<T> {
        Ordering { a, b in
            let result = lhs.compare(a, b)
            return result == .orderedSame ? rhs.compare(a, b) : result
        }
    }
}

extension Ordering: Zero {
    /// Finds every pair the same, so it never decides anything on its own
    public static var zero: Ordering<T> {
        Ordering { _, _ in .orderedSame }
    }
}

extension Ordering: Monoid {}

public extension Sequence {
    func sorted(by ordering: Ordering<Element>) -> [Element] {
        sorted(by: ordering.areInIncreasingOrder)
    }

    func max(by ordering: Ordering<Element>) -> Element? {
        self.max(by: ordering.areInIncreasingOrder)
    }

    func min(by ordering: Ordering<Element>) -> Element? {
        self.min(by: ordering.areInIncreasingOrder)
    }
}

public extension MutableCollection where Self: RandomAccessCollection {
    mutating func sort(by ordering: Ordering<Element>) {
        sort(by: ordering.areInIncreasingOrder)
    }
}
