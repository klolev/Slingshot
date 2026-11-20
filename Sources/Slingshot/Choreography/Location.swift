/// A set of nodes. Declared with `@Locations` and the `Includes` of each member:
///
///     @Locations
///     enum Peers: Initiator.Includes, Responder.Includes {}
///
public protocol LocationSet: Sendable {
    static var members: [any Location.Type] { get }

    /// Shared effects that every member in this set can use. Defaults to NoEffects
    /// `typealias Shared = PeerShared`
    associatedtype Shared: EffectStack

    /// A program in the set's shared effects, as one of its members' local program.
    static func lift<L: Location, V: ~Copyable>(_ program: consuming Freer<Shared, V>, at member: Member<L, Self>) -> Freer<L.Local, V>
}

public extension LocationSet {
    static func contains(_ location: any Location.Type) -> Bool {
        members.contains { ObjectIdentifier($0) == ObjectIdentifier(location) }
    }
}

public protocol Location: LocationSet where Shared == Local {
    static var name: String { get }

    /// Reads the values this location holds
    associatedtype Reader: LocationReader

    /// The effects this location's local code can use. By default, just `Embedding`.
    associatedtype Local: EffectStack = Embedding.Family
}

public extension Location {
    static var members: [any Location.Type] { [Self.self] }
}

/// Only compiles when `Stack` is an effect stack: `@Location` and `@Locations` name it with `Local` and `Shared`,
/// so declaring one that isn't a stack fails right there instead of where the location is first used.
/// A family is the stack `SomeFamily.Family`, not the `@EffectFamily` enum itself.
public enum EffectStackCheck<Stack: EffectStack> {}

/// What `@Location` generates as `Reader`. Only internally built in `locally`
public protocol LocationReader {
    /// For generated code only
    init(_unchecked: Void)
}

/// A proof that `L` is in `S`, for code that's generic over its locations.
/// Get one from `L.member(of: S.self)`, which only compiles when `S` conforms to `L.Includes`.
public struct Member<L: Location, S: LocationSet>: Sendable {
    /// Only for `@Location`'s `member(of:)`: making one by hand claims a membership the compiler hasn't checked
    public init(_unchecked: Void) {}

    /// Reads a value held by `S`, at `L`
    public func read<V: ~Copyable>(_ v: consuming At<S, V>, with reader: L.Reader) -> V {
        v.take()
    }
}

/// A proof that every location in `Sub` is in `Outer`, for `conclave`.
/// Get one from `Sub.subset(of: Outer.self)`, which only compiles when `Outer` conforms to each member's `Includes`.
public struct Subset<Sub: LocationSet, Outer: LocationSet>: Sendable {
    /// Only for the generated `subset(of:)`: making one by hand claims an inclusion the compiler hasn't checked
    public init(_unchecked: Void) {}
}

public extension Subset where Sub == Outer {
    /// Every set is a subset of itself
    static var whole: Self { .init(_unchecked: ()) }
}

/// Reads the values every member of `S` holds, inside `congruently`.
public struct Congruent<S: LocationSet> {
    init() {}

    public func callAsFunction<V>(_ v: At<S, V>) -> V {
        v.take()
    }
}

#if Macros
/// Makes an enum a location: its `name`, its `Reader`, the `Includes` protocol that sets containing it conform to,
/// and `member(of:)`, the proof that a set contains it.
///
///     @Location enum Server {}
@attached(member, names: named(name), named(Includes), named(Reader), named(member), named(subset), named(locally), named(Local), named(Shared), named(lift), named(LocalIsAnEffectStack))
@attached(extension, conformances: Location)
public macro Location() = #externalMacro(module: "SlingshotMacros", type: "LocationMacro")

/// Makes an enum the set of the locations it conforms to the `Includes` of.
///
///     @Locations enum Peers: Initiator.Includes, Responder.Includes {}
///
/// Declare `typealias Shared = SomeStack` inside it for effects every member's `parallel` body can use.
///
/// It also generates `faceted(…)`, one labelled value per member, which makes them the set's facets without communicating,
/// from values each member holds, or from constants as a choreography step:
///
///     let ids: Faceted<Peers, SessionID> = Peers.faceted(initiator: fromCreated, responder: fromJoined)
///     let roles = bind(Peers.faceted(initiator: Role.initiator, responder: .responder))
@attached(member, names: named(members), named(subset), named(Shared), named(lift), named(SharedIsAnEffectStack), named(faceted))
public macro Locations() = #externalMacro(module: "SlingshotMacros", type: "LocationsMacro")
#endif

