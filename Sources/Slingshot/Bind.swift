// Do-notation for the short-circuiting monads, built on typed throws: inside `run`, `try x.bind()` is `>>=`.
// It works because these monads run the rest of the block at most once; `#do` covers the others.
//
//     let total: Int? = Optional.run {
//         let a = try Int("4").bind()
//         let b = try Int("2").bind()
//         return a + b
//     }

/// Thrown by `Optional.bind()` to leave the enclosing `Optional.run` with `nil`.
public struct OptionalBindFailure: Error {
    init() {}
}

/// Thrown by `Either.bind()` to leave the enclosing `Either.run` with its `left`.
// Unchecked: the payload is internal, so only the `run` that catches it can read it
public struct EitherBindFailure<L>: Error, @unchecked Sendable {
    let left: L
}

// `run` takes an untyped throwing closure: Swift infers closure literals as `throws(any Error)`,
// so a typed parameter would force an annotation on every block.

public extension Optional {
    /// Unwraps the value, or leaves the enclosing `run` with `nil`.
    func bind() throws(OptionalBindFailure) -> Wrapped {
        guard let self else { throw OptionalBindFailure() }
        return self
    }

    /// Any other error thrown by `body` also becomes `nil`, like `try?`.
    static func run(_ body: () throws -> Wrapped) -> Wrapped? {
        try? body()
    }

    nonisolated(nonsending) static func run(_ body: nonisolated(nonsending) () async throws -> Wrapped) async -> Wrapped? {
        try? await body()
    }
}

public extension Either {
    /// Unwraps the `right`, or leaves the enclosing `run` with this `left`.
    func bind() throws(EitherBindFailure<L>) -> R {
        switch self {
        case .right(let r):
            return r
        case .left(let l):
            throw EitherBindFailure(left: l)
        }
    }

    /// Errors other than a failed `bind` are rethrown: they can't become an `L`.
    static func run(_ body: () throws -> R) rethrows -> Either<L, R> {
        do {
            return .right(try body())
        } catch let failure as EitherBindFailure<L> {
            return .left(failure.left)
        }
    }

    nonisolated(nonsending) static func run(_ body: nonisolated(nonsending) () async throws -> R) async rethrows -> Either<L, R> {
        do {
            return .right(try await body())
        } catch let failure as EitherBindFailure<L> {
            return .left(failure.left)
        }
    }
}

public extension Result {
    /// Unwraps the success, or leaves the enclosing `run` with this failure.
    func bind() throws(Failure) -> Success {
        try get()
    }

    /// Errors that aren't a `Failure` are rethrown.
    static func run(_ body: () throws -> Success) rethrows -> Result<Success, Failure> {
        do {
            return .success(try body())
        } catch let failure as Failure {
            return .failure(failure)
        }
    }

    nonisolated(nonsending) static func run(_ body: nonisolated(nonsending) () async throws -> Success) async rethrows -> Result<Success, Failure> {
        do {
            return .success(try await body())
        } catch let failure as Failure {
            return .failure(failure)
        }
    }
}
