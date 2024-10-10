extension String {
    public struct NonEmpty {
        public let first: Character
        let container: String
        
        enum CodingKeys: String, CodingKey {
            case first
            case container
        }
        
        public init(first: Character, container: String) {
            self.first = first
            self.container = container
        }
        
        public init?(container: String) {
            guard let first = container.first else { return nil }
            self.first = first
            self.container = container
        }
    }
}

public extension String.NonEmpty {
    var erased: String {
        container
    }
}
extension String.NonEmpty: Sequence {
    public typealias Iterator = String.Iterator
    public typealias Element = String.Element

    public func makeIterator() -> Self.Iterator {
        container.makeIterator()
    }
}

public extension String.NonEmpty {
    func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let minimum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, minimum) ? first : minimum
    }

    func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let maximum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, maximum) ? maximum : first
    }
}


extension String.NonEmpty: Collection {
	public typealias Index = String.Index
	public typealias Indices = String.Indices
	public subscript(position: Self.Index) -> Self.Element { self.container[position] }
	public var startIndex: Self.Index { self.container.startIndex }
	public var endIndex: Self.Index { self.container.endIndex }
	public var indices: Self.Indices { self.container.indices }
	public func index(after i: Self.Index) -> Self.Index { self.container.index(after: i) }
}

extension String.NonEmpty: BidirectionalCollection {
	public func index(before i: Self.Index) -> Self.Index { self.container.index(before: i) }
}

extension String.NonEmpty: Equatable {
	public static func == (lhs: Self, rhs: Self) -> Bool { lhs.container == rhs.container }
}

extension String.NonEmpty: Hashable {
	public func hash(into hasher: inout Hasher) -> Void { self.container.hash(into: &hasher) }
}

extension String.NonEmpty: Comparable {
	public static func < (lhs: Self, rhs: Self) -> Bool { lhs.container < rhs.container }
}

extension String.NonEmpty: Semigroup {
    public static func <> (lhs: Self, rhs: Self) -> Self {
        Self(first: lhs.first, container: lhs.container <> rhs.container)
    }
}


extension String.NonEmpty {
    public static func pure(_ x: Character) -> Self {
        Self(first: x, container: .pure(x))
    }
}
