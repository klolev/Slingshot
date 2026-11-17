/// A value each location in `S` holds its own version of, like each peer's nonce: same type, possibly different values.
/// Made by `parallel`; a location in `S` reads its own facet with its reader, and `fanIn` gathers them all.
/// Copyable exactly when its value is: a noncopyable one, like each peer's session, is used with
/// `parallel(consuming:)` or read with `parallel(borrowing:)`.
public struct Faceted<S: LocationSet, Value: ~Copyable>: ~Copyable {
    var value: Value?
    /// The location holding `value`, by name: a `parallel` body over the facets runs there
    var holder: String?

    /// Within Slingshot only: outside it, a facet only comes from `parallel` or `faceted(…)`
    init(value: consuming Value?, at location: (any Location.Type)?) {
        self.value = value
        self.holder = location?.name
    }

    /// Whether this node holds a facet
    var isHeld: Bool {
        switch value {
        case .some: true
        case .none: false
        }
    }

    public static var absent: Self { .init(value: nil, at: nil) }

    /// Only for projection and `@Location`'s generated readers: inside a choreography, read with a location's reader
    public consuming func take() -> Value {
        switch consume value {
        case .some(let value):
            return value
        case .none:
            preconditionFailure("this node holds no facet of \(S.self)")
        }
    }

    /// The location holding the facet: only asked where it's held, which is always one of `S`'s members
    private var holderLocation: any Location.Type {
        guard let holder, let location = S.members.first(where: { $0.name == holder }) else {
            preconditionFailure("a facet of \(S.self) held outside its members")
        }
        return location
    }

    /// The facet transformed where it's held, with the location holding it
    consuming func map<Mapped: ~Copyable>(_ transform: (any Location.Type, consuming Value) -> Mapped) -> Faceted<S, Mapped> {
        let location: (any Location.Type)? = isHeld ? holderLocation : nil
        switch consume value {
        case .some(let value):
            return Faceted<S, Mapped>(value: transform(location!, value), at: location)
        case .none:
            return .absent
        }
    }

    /// A transformation of the facet where it's held, leaving the facet itself in place
    borrowing func borrowMap<Mapped: ~Copyable>(_ transform: (any Location.Type, borrowing Value) -> Mapped) -> Faceted<S, Mapped> {
        switch value {
        case .some(let value):
            let location = holderLocation
            return Faceted<S, Mapped>(value: transform(location, value), at: location)
        case .none:
            return .absent
        }
    }
    
    borrowing func borrowAt<Mapped: ~Copyable, L: Location>(at location: L.Type, _ transform: (borrowing Value) -> Mapped) -> At<L, Mapped> {
        guard holder == L.name else {
            return .absent
        }
        
        return switch value {
        case .some(let value):
            .init(value: transform(value))
        case .none:
            .absent
        }
    }
}
extension Faceted: Copyable where Value: Copyable {}
extension Faceted: Sendable where Value: Sendable & ~Copyable {}

extension Faceted where Value: ~Copyable {
    /// Only for `@Locations`' `faceted(…)`, which adds one value per member of `S`, starting from `absent`: a member's
    /// value becomes this node's facet where it's held. Used any other way, it claims facets the compiler hasn't checked.
    public consuming func _unchecked<L: Location>(adding piece: consuming At<L, Value>) -> Faceted<S, Value> {
        switch piece.release() {
        case .some(let value):
            // the members are all different, so a node holds at most one of their values
            return Faceted(value: value, at: L.self)
        case .none:
            return self
        }
    }
}

/// Reads what the location running a `parallel` body holds: values held by all of `S`, and its own facets.
public struct Facet<S: LocationSet> {
    /// The location this body is running at
    public let location: any Location.Type

    init(location: any Location.Type) {
        self.location = location
    }

    public func callAsFunction<V: ~Copyable>(_ v: consuming At<S, V>) -> V {
        v.take()
    }

    public func callAsFunction<V: ~Copyable>(_ facets: consuming Faceted<S, V>) -> V {
        facets.take()
    }
}

public extension Facet {
    /// Every other member's facet in a quire gathered from `S`, in the order of `S.members`: for a pair, the peer's
    func others<V>(_ quire: Quire<S, V>) -> [V] {
        S.members.filter { $0.name != location.name }.map { quire.values[$0.name]! }
    }
}
