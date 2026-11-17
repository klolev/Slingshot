/// A value held by every location in `S`. At any other location it's empty.
/// Copyable exactly when its value is: a noncopyable one, like a session, is used once with `locally(consuming:)`,
/// or read with `locally(borrowing:)`.
public struct At<S: LocationSet, Value: ~Copyable>: ~Copyable {
    var value: Value?

    /// Within Slingshot only: outside it, a value only becomes located through a choreography
    init(value: consuming Value?) {
        self.value = value
    }

    /// Whether this node holds the value
    var isHeld: Bool {
        switch value {
        case .some: true
        case .none: false
        }
    }

    public static var absent: Self { .init(value: nil) }

    /// Only for projection and `@Location`'s generated readers: inside a choreography, read with a location's reader
    public consuming func take() -> Value {
        switch consume value {
        case .some(let value):
            return value
        case .none:
            preconditionFailure("\(Value.self) isn't held at this location")
        }
    }
}
extension At: Copyable where Value: Copyable {}
extension At: Sendable where Value: Sendable & ~Copyable {}

extension At where Value: ~Copyable {
    /// The value transformed where it's held, and still absent elsewhere
    consuming func map<Mapped: ~Copyable>(_ transform: (consuming Value) -> Mapped) -> At<S, Mapped> {
        switch consume value {
        case .some(let value):
            return At<S, Mapped>(value: transform(value))
        case .none:
            return .absent
        }
    }

    /// A transformation of the value where it's held, leaving the value itself in place
    borrowing func borrowMap<Mapped: ~Copyable>(_ transform: (borrowing Value) -> Mapped) -> At<S, Mapped> {
        switch value {
        case .some(let value):
            return At<S, Mapped>(value: transform(value))
        case .none:
            return .absent
        }
    }
}

extension At where Value: ~Copyable {
    /// The value where it's held, nil elsewhere
    consuming func release() -> Value? {
        switch consume value {
        case .some(let value):
            return value
        case .none:
            return nil
        }
    }
}

/// Every location of `S`'s facet, gathered by `fanIn`: one value per member.
public struct Quire<S: LocationSet, Value> {
    var values: [String: Value]

    /// The facet of one member: the proof makes asking for a non-member a compile error
    public subscript<L: Location>(_ member: Member<L, S>) -> Value {
        values[L.name]!
    }

    /// Every facet, in the order of `S.members`
    public var all: [Value] {
        S.members.map { values[$0.name]! }
    }
}
extension Quire: Sendable where Value: Sendable {}

