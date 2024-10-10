extension Dictionary {
    public struct NonEmpty {
        public let first: (key: Key, value: Value)
        let container: Dictionary
        
        enum CodingKeys: String, CodingKey {
            case first
            case container
        }
        
        public init(first: (key: Key, value: Value), container: Dictionary) {
            self.first = first
            self.container = container
        }
        
        public init?(container: Dictionary) {
            guard let first = container.first else { return nil }
            self.first = first
            self.container = container
        }
    }
}

public extension Dictionary.NonEmpty {
    var erased: Dictionary {
        container
    }
}
extension Dictionary.NonEmpty: Sequence {
    public typealias Iterator = Dictionary.Iterator
    public typealias Element = Dictionary.Element

    public func makeIterator() -> Self.Iterator {
        container.makeIterator()
    }
}

public extension Dictionary.NonEmpty {
    func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let minimum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, minimum) ? first : minimum
    }

    func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
        guard let maximum = try container.min(by: areInIncreasingOrder) else { return first }

        return try areInIncreasingOrder(first, maximum) ? maximum : first
    }
}


extension Dictionary.NonEmpty: Sendable where Dictionary.Element: Sendable {}


extension Dictionary.NonEmpty: Collection {
	public typealias Index = Dictionary.Index
	public typealias Indices = Dictionary.Indices
	public subscript(position: Self.Index) -> Self.Element { self.container[position] }
	public var startIndex: Self.Index { self.container.startIndex }
	public var endIndex: Self.Index { self.container.endIndex }
	public var indices: Self.Indices { self.container.indices }
	public func index(after i: Self.Index) -> Self.Index { self.container.index(after: i) }
}

extension Dictionary.NonEmpty: Equatable where Key: Equatable, Value: Equatable {
	public static func == (lhs: Self, rhs: Self) -> Bool { lhs.container == rhs.container }
}

extension Dictionary.NonEmpty: Hashable where Value: Hashable {
	public func hash(into hasher: inout Hasher) -> Void { self.container.hash(into: &hasher) }
}

extension Dictionary.NonEmpty: Semigroup {
    public static func <> (lhs: Self, rhs: Self) -> Self {
        Self(first: lhs.first, container: lhs.container <> rhs.container)
    }
}


extension Dictionary.NonEmpty {
    public static func pure(_ x: (key: Key, value: Value)) -> Self {
        Self(first: x, container: .pure(x))
    }
}
