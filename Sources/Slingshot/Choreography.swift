// Heavily basde on HasChor, a Haskell library for choreographic programming,
// where choreographies are ordinary monadic code and projection happens by interpreting the same code once per participant

import Foundation

/// nodes in a distributed system, identified by a string
public protocol Location: Sendable {
    static var name: String { get }
}

/// a @ l represents a value of type a at location l. At any other location it’s empty.
public struct At<L: Location, Value> {
    fileprivate var value: Value?
    
    public static var absent: Self { .init() }
    
    public func take() -> Value {
        value!
    }
}
extension At: Sendable where Value: Sendable {}

public struct Unwrap<L: Location> {
    fileprivate init() {}
    
    public func callAsFunction<V>(_ v: At<L, V>) -> V {
        guard let value = v.value else {
            preconditionFailure("Unwrapped a \(V.self) located at \(L.name), but it's empty here, which shouldn't be possible.")
        }
        return value
    }
}

@EffectFamily
public enum Choreography {
    public protocol Interpreter {
        /// runs a local computation at one location L
        func locally<L: Location, ComputationOutput>(
            _ type: L.Type,
            _ body: @escaping (Unwrap<L>) async throws -> ComputationOutput
        ) async throws -> At<L, ComputationOutput>
        
        /// sends a value V at location S to location R
        func send<Sender: Location, Receiver: Location, Value: Codable & Sendable>(
            _ v: At<Sender, Value>,
            to: Receiver.Type
        ) async throws -> At<Receiver, Value>
        
        /// branches depending on value V at location L
        func branch<L: Location, Value: Codable & Sendable, BranchOutput>(
            _ v: At<L, Value>,
            _ body: @escaping (Value) -> Freer<Choreography.Family, BranchOutput>
        ) async throws -> BranchOutput
    }
}

@EffectFamily
public enum Networking {
    public protocol Interpreter {
        func send<V: Codable & Sendable>(_ value: V, to location: String) async throws
        func receive<V: Codable & Sendable>(_ type: V.Type, from location: String) async throws -> V
        func broadcast<V: Codable & Sendable>(_ value: V) async throws
    }
}

@EffectFamily
public enum Embedding {
    public protocol Interpreter {
        func run<V>(_ body: @escaping () async throws -> V) async throws -> V
    }
}

public struct Projector<Me: Location, Effs: Networking.Has & Embedding.Has>: Choreography.Translation {
    public typealias Target = Effs
    
    public func locally<L, ComputationOutput>(
        _ type: L.Type,
        _ body: @escaping (Unwrap<L>) async throws -> ComputationOutput
    ) -> Freer<Effs, At<L, ComputationOutput>> where L : Location {
        guard Me.self == L.self else {
            return .pure(.absent)
        }
        
        return Embedding.run {
            .init(value: try await body(.init()))
        }
    }
    
    public func send<Sender, Receiver, Value>(
        _ v: At<Sender, Value>,
        to: Receiver.Type
    ) -> Freer<Effs, At<Receiver, Value>> where Sender : Location, Receiver : Location, Value : Codable & Sendable {
        if Sender.self == Receiver.self, Sender.self == Me.self {
            return .pure(.init(value: v.take()))
        }
        
        if Sender.self == Me.self {
            return Networking.send(v.take(), to: Receiver.name)
                .map(constant(.absent))
        }
        
        if Receiver.self == Me.self {
            return Networking.receive(Value.self, from: Sender.name)
                .map(At.init(value:))
        }
        
        return .pure(.absent)
    }
    
    public func branch<L, Value, BranchOutput>(
        _ v: At<L, Value>,
        _ body: @escaping (Value) -> Freer<Choreography.Family, BranchOutput>
    ) -> Freer<Effs, BranchOutput> where L : Location, Value: Codable & Sendable {
        let broadcast: Freer<Effs, Value> = if Me.self == L.self {
            Networking.broadcast(v.take())
                .map(constant(v.take()))
        } else {
            Networking.receive(Value.self, from: L.name)
        }
        
        return broadcast.flatMap {
            Choreography.translate(body($0), with: self)
        }
    }
}
