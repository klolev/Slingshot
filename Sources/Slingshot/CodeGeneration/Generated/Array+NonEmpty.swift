extension Array {
    public struct NonEmpty {
        public let first: Element
        let container: Array<Element>
        
        enum CodingKeys: String, CodingKey {
            case first
            case container
        }
        
        public init(first: Element, container: Array<Element>) {
            self.first = first
            self.container = container
        }
        
        public init?(container: Array<Element>) {
            guard let first = container.first else { return nil }
            self.first = first
            self.container = container
        }
    }
}

public extension Array.NonEmpty {
    var erased: Array<Element> {
        container
    }
}
extension Array.NonEmpty: Sequence {
    public typealias Iterator = Array.Iterator
    public typealias Element = Array.Element

    public func makeIterator() -> Self.Iterator {
        container.makeIterator()
    }
}

public extension Array.NonEmpty {
    func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let minimum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, minimum) ? first : minimum
    }

    func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let maximum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, maximum) ? maximum : first
    }
}


public extension Array.NonEmpty where Element: Comparable {
    func min() -> Element {
        min(by: { $0 < $1 })
    }

    func max() -> Element {
        max(by: { $0 < $1 })
    }
}


extension Array.NonEmpty: Sendable where Array.Element: Sendable {}


extension Array.NonEmpty: Collection {
	public typealias Index = Array.Index
	public typealias Indices = Array.Indices
	public subscript(position: Self.Index) -> Self.Element { self.container[position] }
	public var startIndex: Self.Index { self.container.startIndex }
	public var endIndex: Self.Index { self.container.endIndex }
	public var indices: Self.Indices { self.container.indices }
	public func index(after i: Self.Index) -> Self.Index { self.container.index(after: i) }
}

extension Array.NonEmpty: BidirectionalCollection {
	public func index(before i: Self.Index) -> Self.Index { self.container.index(before: i) }
}

extension Array.NonEmpty: Hashable where Element: Hashable {
	public func hash(into hasher: inout Hasher) -> Void { self.container.hash(into: &hasher) }
}

extension Array.NonEmpty: Equatable where Element: Equatable {
	public static func == (lhs: Self, rhs: Self) -> Bool { lhs.container == rhs.container }
}

extension Array.NonEmpty: RandomAccessCollection {
	public func distance(from start: Self.Index, to end: Self.Index) -> Int { self.container.distance(from: start, to: end) }
	public func index(_ i: Self.Index, offsetBy distance: Int) -> Self.Index { self.container.index(i, offsetBy: distance) }
	public func index(_ i: Self.Index, offsetBy distance: Int, limitedBy limit: Self.Index) -> Self.Index? { self.container.index(i, offsetBy: distance, limitedBy: limit) }
}

extension Array.NonEmpty: Semigroup {
    public static func <> (lhs: Self, rhs: Self) -> Self {
        Self(first: lhs.first, container: lhs.container <> rhs.container)
    }
}


extension Array.NonEmpty {
    public static func pure(_ x: Element) -> Self {
        Self(first: x, container: .pure(x))
    }
}


public extension Array.NonEmpty {
    func map<T>(_ transform: @escaping (Element) -> T) -> Array<T>.NonEmpty {
        .init(first: transform(first), container: container.map(transform))
    }
}
