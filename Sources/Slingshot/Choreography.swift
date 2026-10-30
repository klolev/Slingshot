// Heavily basde on HasChor, a Haskell library for choreographic programming,
// where choreographies are ordinary monadic code and projection happens by interpreting the same code once per participant

import Foundation

/// nodes in a distributed system, identified by a string
public protocol Location {
    static var name: String { get }
}

/// a @ l represents a value of type a at location l. At any other location it’s empty.
public struct At<L: Location, Value: Sendable>: Sendable {
    fileprivate let value: Value?
}

public struct Unwrap<L: Location> {
    fileprivate init() {}
    
    public func callAsFunction<V>(_ v: At<L, V>) -> V {
        guard let value = v.value else {
            preconditionFailure("Unwrapped a \(V.self) located at \(L.name), but it's empty here, which shouldn't be possible.")
        }
        return value
    }
}

public protocol Choreographer {
    /// runs a local computation at one location L
    func locally<L: Location, V>(_: L.Type, _ body: (Unwrap<L>) async throws -> V) async throws -> At<L, V>
    
    /// communicates a value V at location S to location R
    func comm<S: Location, R: Location, V: Codable>(_ v: At<S, V>, from: S.Type, to: R.Type) async throws -> At<R, V>
    
    /// branches depending on value V at location L
    func cond<L: Location, V: Codable & CaseIterable, B>(_ v: At<L, V>, _ body: (V) async throws -> B) async throws -> B
}

public final class TracingChoreographer: Choreographer {
    public indirect enum Trace: Equatable {
        case locally(String)
        case comm(from: String, to: String, type: String)
        case cond(at: String, cases: [(String, [Trace])])
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.locally(let a), .locally(let b)):
                a == b
            case (.comm(let fromA, let toA, let typeA), .comm(from: let fromB, to: let toB, type: let typeB)):
                fromA == fromB && toA == toB && typeA == typeB
            case (.cond(let atA, let casesA), .cond(at: let atB, cases: let casesB)):
                atA == atB && casesA.count == casesB.count && zip(casesA, casesB).allSatisfy { a, b in
                    a.0 == b.0 && a.1 == b.1
                }
            default:
                false
            }
        }
    }
    
    private(set) var events: [Trace] = []

    public func locally<L, V>(_: L.Type, _ body: (Unwrap<L>) async throws -> V) async throws -> At<L, V> {
        events.append(.locally(L.name))
        return At(value: nil)
    }

    public func comm<S, R, V: Codable>(_ v: At<S, V>, from: S.Type, to: R.Type) async throws -> At<R, V> {
        events.append(.comm(from: S.name, to: R.name, type: "\(V.self)"))
        return At(value: nil)
    }

    public func cond<L, V: Codable & CaseIterable, B>(_ v: At<L, V>, _ body: (V) async throws -> B) async throws -> B {
        var arms: [(String, [Trace])] = []
        var last: B?
        for choice in V.allCases {
            let sub = TracingChoreographer()
            last = try await body(choice)
            arms.append(("\(choice)", sub.events))
        }
        events.append(.cond(at: L.name, cases: arms))
        return last!
    }
}

public protocol ChoreographerNetwork: Sendable {
    func send(_ data: Data, to: String) async throws
    func receive(from: String) async throws -> Data
    func broadcast(_ data: Data) async throws
}

public struct StandardChoreographer: Sendable {
    public let me: String
    let net: any ChoreographerNetwork

    public func locally<L: Location, V>(_: L.Type, _ body: (Unwrap<L>) async throws -> V) async throws -> At<L, V> {
        guard me == L.name else { return At(value: nil) }
        return At(value: try await body(Unwrap()))
    }

    public func comm<S: Location, R: Location, V: Codable>(
        _ v: At<S, V>, from _: S.Type, to _: R.Type) async throws -> At<R, V> {
        if me == S.name { try await net.send(try JSONEncoder().encode(v.value!), to: R.name) }
        if me == R.name { return At(value: try JSONDecoder().decode(V.self, from: try await net.receive(from: S.name))) }
        return At(value: nil)
    }

    /// Everyone learns L's choice, then follows the same branch
    public func cond<L: Location, V: Codable, B>(
        _ v: At<L, V>, _ body: (V) async throws -> B) async throws -> B {
        let choice: V
        if me == L.name { choice = v.value!; try await net.broadcast(try JSONEncoder().encode(choice)) }
        else { choice = try JSONDecoder().decode(V.self, from: try await net.receive(from: L.name)) }
        return try await body(choice)
    }
}
