import Foundation

/// A pair, as a type: copyable exactly when both values are, so it can also hold noncopyable values,
/// which a Swift tuple can't. `#do` uses it to combine independent binds.
public struct Tuple<First: ~Copyable, Second: ~Copyable>: ~Copyable {
    // var, so a consuming split can move a noncopyable value out; only Slingshot can set them
    public internal(set) var first: First
    public internal(set) var second: Second

    public init(_ first: consuming First, _ second: consuming Second) {
        self.first = first
        self.second = second
    }
}
extension Tuple: Copyable where First: Copyable, Second: Copyable {}
extension Tuple: Sendable where First: Sendable & ~Copyable, Second: Sendable & ~Copyable {}

public extension Tuple where First: ~Copyable, Second: ~Copyable {
    /// Both values, as parameters: a consuming method, so they move out without a closure capturing them
    consuming func split<R: ~Copyable>(_ body: (consuming First, consuming Second) throws -> R) rethrows -> R {
        try body(first, second)
    }
}

extension Tuple: Equatable where First: Equatable, Second: Equatable {}
extension Tuple: Hashable where First: Hashable, Second: Hashable {}
extension Tuple: Decodable where First: Decodable, Second: Decodable {}
extension Tuple: Encodable where First: Encodable, Second: Encodable {}
