public extension Optional {
    func traverse<T>(_ transform: @escaping (Wrapped) -> Promise<T>) -> Promise<Optional<T>> {
        switch self {
        case .some(let x):
            return transform(x).map(Optional<T>.some)
        case .none:
            return .pure(.none)
        }
    }
}

public extension Optional {
    func traverse<T>(_ transform: @escaping (Wrapped) -> Optional<T>) -> Optional<Optional<T>> {
        switch self {
        case .some(let x):
            return transform(x).map(Optional<T>.some)
        case .none:
            return .pure(.none)
        }
    }
}

public extension Optional {
    func traverse<T, Failure>(_ transform: @escaping (Wrapped) -> Result<T, Failure>) -> Result<Optional<T>, Failure> {
        switch self {
        case .some(let x):
            return transform(x).map(Optional<T>.some)
        case .none:
            return .pure(.none)
        }
    }
}

public extension Optional {
    func traverse<T, Failure>(_ transform: @escaping (Wrapped) -> Validation<Failure, T>) -> Validation<Failure, Optional<T>> {
        switch self {
        case .some(let x):
            return transform(x).map(Optional<T>.some)
        case .none:
            return .pure(.none)
        }
    }
}

public extension Optional {
    func traverse<T, L>(_ transform: @escaping (Wrapped) -> Either<L, T>) -> Either<L, Optional<T>> {
        switch self {
        case .some(let x):
            return transform(x).map(Optional<T>.some)
        case .none:
            return .pure(.none)
        }
    }
}

public extension Optional where Wrapped: PromiseProtocol {
    var sequenced: Promise<Optional<Wrapped.Value>> {
        traverse(\.promise)
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