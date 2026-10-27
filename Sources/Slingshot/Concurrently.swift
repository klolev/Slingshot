import Foundation

public protocol ConcurrentlyProtocol: Sendable {
    associatedtype Value: Sendable

    var concurrently: Concurrently<Value> { get }
}

/// An async computation whose applicative runs effects concurrently, the Sendable counterpart of `IO`.
/// There's no `flatMap`: a bind has to wait for its input, which would contradict the concurrent `ap`.
/// Drop to `io` to sequence steps.
public struct Concurrently<Value: Sendable>: Sendable {
    let _f: @Sendable () async -> Value

    public init(_ f: @escaping @Sendable () async -> Value) {
        self._f = f
    }

    public var value: Value {
        get async {
            await _f()
        }
    }

    public var io: IO<Value> {
        IO(_f)
    }
}

extension Concurrently: ConcurrentlyProtocol {
    public var concurrently: Concurrently<Value> { self }
}

public extension Concurrently {
    /// Runs throwing work, capturing its error in a `Result` so it composes with `Result` traversals.
    init<Success, Failure>(catching body: @escaping @Sendable () async throws(Failure) -> Success) where Value == Result<Success, Failure> {
        self.init {
            do throws(Failure) {
                return .success(try await body())
            } catch {
                return .failure(error)
            }
        }
    }
}
