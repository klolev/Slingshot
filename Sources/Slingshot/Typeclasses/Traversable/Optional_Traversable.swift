public extension Optional {
    func traverse<T>(_ transform: @escaping (Wrapped) -> Optional<T>) -> Optional<Optional<T>> {
        switch self {
        case .some(let x):
            transform(x).map(Optional<T>.some)
        case .none:
            .pure(.none)
        }
    }

    func traverse<T, Failure>(_ transform: @escaping (Wrapped) -> Result<T, Failure>) -> Result<Optional<T>, Failure> {
        switch self {
        case .some(let x):
            transform(x).map(Optional<T>.some)
        case .none:
            .pure(.none)
        }
    }

    func traverse<T, Failure>(_ transform: @escaping (Wrapped) -> Validation<Failure, T>) -> Validation<Failure, Optional<T>> {
        switch self {
        case .some(let x):
            transform(x).map(Optional<T>.some)
        case .none:
            .pure(.none)
        }
    }

    func traverse<T, L>(_ transform: @escaping (Wrapped) -> Either<L, T>) -> Either<L, Optional<T>> {
        switch self {
        case .some(let x):
            transform(x).map(Optional<T>.some)
        case .none:
            .pure(.none)
        }
    }

    func traverse<T>(_ transform: @escaping (Wrapped) -> IO<T>) -> IO<Optional<T>> {
        switch self {
        case .some(let x):
            transform(x).map(Optional<T>.some)
        case .none:
            .pure(.none)
        }
    }
}

public extension Optional where Wrapped: Sendable {
    func traverse<T>(_ transform: @escaping @Sendable (Wrapped) -> Concurrently<T>) -> Concurrently<Optional<T>> {
        switch self {
        case .some(let x):
            transform(x).map { .some($0) }
        case .none:
            .pure(.none)
        }
    }

    func traverse<T>(_ transform: @escaping @Sendable (Wrapped) -> Concurrently<Optional<T>>) -> Concurrently<Optional<Optional<T>>> {
        switch self {
        case .some(let x):
            transform(x).map { $0.map { .some($0) } }
        case .none:
            .pure(.some(.none))
        }
    }

    func traverse<T, Failure>(_ transform: @escaping @Sendable (Wrapped) -> Concurrently<Result<T, Failure>>) -> Concurrently<Result<Optional<T>, Failure>> {
        switch self {
        case .some(let x):
            transform(x).map { $0.map { .some($0) } }
        case .none:
            .pure(.success(.none))
        }
    }

    func traverse<T, L>(_ transform: @escaping @Sendable (Wrapped) -> Concurrently<Either<L, T>>) -> Concurrently<Either<L, Optional<T>>> {
        switch self {
        case .some(let x):
            transform(x).map { $0.map { .some($0) } }
        case .none:
            .pure(.right(.none))
        }
    }
}

public extension Optional where Wrapped: OptionalProtocol {
    var sequenced: Optional<Optional<Wrapped.Wrapped>> {
        traverse(\.value)
    }
}

public extension Optional where Wrapped: ResultProtocol {
    var sequenced: Result<Optional<Wrapped.Success>, Wrapped.Failure> {
        traverse(\.result)
    }
}

public extension Optional where Wrapped: ValidationProtocol {
    var sequenced: Validation<Wrapped.Failure, Optional<Wrapped.Value>> {
        traverse(\.validation)
    }
}

public extension Optional where Wrapped: EitherProtocol {
    var sequenced: Either<Wrapped.L, Optional<Wrapped.R>> {
        traverse(\.either)
    }
}

public extension Optional where Wrapped: IOProtocol {
    var sequenced: IO<Optional<Wrapped.Value>> {
        traverse(\.io)
    }
}

public extension Optional where Wrapped: ConcurrentlyProtocol {
    var sequenced: Concurrently<Optional<Wrapped.Value>> {
        traverse(\.concurrently)
    }
}
