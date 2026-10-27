import Foundation

public protocol IOProtocol {
    associatedtype Value

    var io: IO<Value> { get }
}

public struct IO<Value> {
    // nonsending all the way down: the computation runs on whichever actor awaits it
    let _f: nonisolated(nonsending) () async -> Value
    
    public init(_ f: @escaping (nonisolated(nonsending) () async -> Value)) {
        self._f = f
    }
    
    /// Runs on the caller's actor, so a non-Sendable `IO` can be awaited from actor-isolated code.
    nonisolated(nonsending) public var value: Value {
        get async {
            await _f()
        }
    }
}

extension IO: IOProtocol {
    public var io: IO<Value> { self }
}
