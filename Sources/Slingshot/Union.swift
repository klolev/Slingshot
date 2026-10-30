@dynamicMemberLookup
public struct Union<A, B> {
    public let a: A
    public let b: B
    
    public subscript<T>(dynamicMember path: KeyPath<A, T>) -> T {
        a[keyPath: path]
    }
    
    public subscript<T>(dynamicMember path: KeyPath<B, T>) -> T {
        b[keyPath: path]
    }
    
    public init(a: A, b: B) {
        self.a = a
        self.b = b
    }
}

extension Union: Equatable where A: Equatable, B: Equatable {}
extension Union: Hashable where A: Hashable, B: Hashable {}
extension Union: Sendable where A: Sendable, B: Sendable {}

extension Union: Encodable where A: Encodable, B: Encodable {
    public func encode(to encoder: any Encoder) throws {
        try a.encode(to: encoder)
        try b.encode(to: encoder)
    }
}

extension Union: Decodable where A: Decodable, B: Decodable {
    public init(from decoder: any Decoder) throws {
        a = try A(from: decoder)
        b = try B(from: decoder)
    }
}
