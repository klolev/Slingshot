public protocol EitherProtocol {
    associatedtype L
    associatedtype R

    var either: Either<L, R> { get }
}

public enum Either<L, R> {
    case right(R)
    case left(L)
}

public extension Either {
    var left: L? {
        switch self {
        case .left(let x): return .pure(x)
        case .right: return .zero
        }
    }

    var right: R? {
        switch self {
        case .right(let x): return .pure(x)
        case .left: return .zero
        }
    }

    func consume(onLeft: @escaping (L) -> (), onRight: @escaping (R) -> ()) {
        switch self {
        case .left(let x): onLeft(x)
        case .right(let x): onRight(x)
        }
    }

    static func consume(onLeft: @escaping (L) -> (), onRight: @escaping (R) -> ()) -> (Either<L, R>) -> () {
        return { x in x.consume(onLeft: onLeft, onRight: onRight) }
    }

    func mapLeft<C>(_ transform: @escaping (L) throws -> C) rethrows -> Either<C, R> {
        switch self {
        case .right(let x):
            return .right(x)
        case .left(let x):
            return .left(try transform(x))
        }
    }
    
    var swapped: Either<R, L> {
        switch self {
        case .right(let r):
            .left(r)
        case .left(let l):
            .right(l)
        }
    }
}

public extension Either where L: Error {
    var result: Result<R, L> {
        switch self {
        case .right(let r):
            return .success(r)
        case .left(let l):
            return .failure(l)
        }
    }
}

extension Either: EitherProtocol {
    public var either: Either<L, R> { self }
}

extension Either: Sendable where L: Sendable, R: Sendable {}
