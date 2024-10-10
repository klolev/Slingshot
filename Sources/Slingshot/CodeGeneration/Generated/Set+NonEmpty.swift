extension Set {
    public struct NonEmpty {
        public let first: Element
        let container: Set<Element>
        
        enum CodingKeys: String, CodingKey {
            case first
            case container
        }
        
        public init(first: Element, container: Set<Element>) {
            self.first = first
            self.container = container
        }
        
        public init?(container: Set<Element>) {
            guard let first = container.first else { return nil }
            self.first = first
            self.container = container
        }
    }
}

public extension Set.NonEmpty {
    var erased: Set<Element> {
        container
    }
}
extension Set.NonEmpty: Sequence {
    public typealias Iterator = Set.Iterator
    public typealias Element = Set.Element

    public func makeIterator() -> Self.Iterator {
        container.makeIterator()
    }
}

public extension Set.NonEmpty {
    func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let minimum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, minimum) ? first : minimum
    }

    func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let maximum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, maximum) ? maximum : first
    }
}


public extension Set.NonEmpty where Element: Comparable {
    func min() -> Element {
        min(by: { $0 < $1 })
    }

    func max() -> Element {
        max(by: { $0 < $1 })
    }
}


extension Set.NonEmpty: Sendable where Set.Element: Sendable {}


extension Set.NonEmpty: Collection {
	public typealias Index = Set.Index
	public typealias Indices = Set.Indices
	public subscript(position: Self.Index) -> Self.Element { self.container[position] }
	public var startIndex: Self.Index { self.container.startIndex }
	public var endIndex: Self.Index { self.container.endIndex }
	public var indices: Self.Indices { self.container.indices }
	public func index(after i: Self.Index) -> Self.Index { self.container.index(after: i) }
}

extension Set.NonEmpty: Equatable where Element: Equatable {
	public static func == (lhs: Self, rhs: Self) -> Bool { lhs.container == rhs.container }
}

extension Set.NonEmpty: Hashable {
	public func hash(into hasher: inout Hasher) -> Void { self.container.hash(into: &hasher) }
}

extension Set.NonEmpty: Semigroup {
    public static func <> (lhs: Self, rhs: Self) -> Self {
        Self(first: lhs.first, container: lhs.container <> rhs.container)
    }
}


extension Set.NonEmpty {
    public static func pure(_ x: Element) -> Self {
        Self(first: x, container: .pure(x))
    }
}


public extension Set.NonEmpty {
    func map<T>(_ transform: @escaping (Element) -> T) -> Set<T>.NonEmpty {
        .init(first: transform(first), container: container.map(transform))
    }
}
