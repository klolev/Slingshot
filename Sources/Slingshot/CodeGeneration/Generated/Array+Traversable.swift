public extension Array {
    func traverse<T>(_ transform: @escaping (Element) -> IO<T>) -> IO<Array<T>> {
        IO<T>.traverse(self, transform).map { Array<T>($0) }
    }
}

public extension Array where Element: Sendable {
    func traverse<T>(_ transform: @escaping @Sendable (Element) -> Concurrently<T>) -> Concurrently<Array<T>> {
        Concurrently<T>.traverse(self, transform).map { Array<T>($0) }
    }
}

public extension Array {
    func traverse<T>(_ transform: @escaping (Element) -> Optional<T>) -> Optional<Array<T>> {
        Optional<T>.traverse(self, transform).map { Array<T>($0) }
    }
}

public extension Array {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Result<T, Failure>) -> Result<Array<T>, Failure> {
        Result<T, Failure>.traverse(self, transform).map { Array<T>($0) }
    }
}

public extension Array {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Validation<Failure, T>) -> Validation<Failure, Array<T>> {
        Validation<Failure, T>.traverse(self, transform).map { Array<T>($0) }
    }
}

public extension Array {
    func traverse<T, L>(_ transform: @escaping (Element) -> Either<L, T>) -> Either<L, Array<T>> {
        Either<L, T>.traverse(self, transform).map { Array<T>($0) }
    }
}

public extension Array where Element: Sendable {
    func traverse<T>(_ transform: @escaping @Sendable (Element) -> Concurrently<Optional<T>>) -> Concurrently<Optional<Array<T>>> {
        Concurrently<T>.traverse(self, transform).map { $0.map { Array<T>($0) } }
    }
}

public extension Array where Element: Sendable {
    func traverse<T, Failure>(_ transform: @escaping @Sendable (Element) -> Concurrently<Result<T, Failure>>) -> Concurrently<Result<Array<T>, Failure>> {
        Concurrently<T>.traverse(self, transform).map { $0.map { Array<T>($0) } }
    }
}

public extension Array where Element: Sendable {
    func traverse<T, L>(_ transform: @escaping @Sendable (Element) -> Concurrently<Either<L, T>>) -> Concurrently<Either<L, Array<T>>> {
        Concurrently<T>.traverse(self, transform).map { $0.map { Array<T>($0) } }
    }
}

public extension Array where Element: IOProtocol {
    var sequenced: IO<Array<Element.Value>> {
        traverse(\.io)
    }
}

public extension Array where Element: ConcurrentlyProtocol {
    var sequenced: Concurrently<Array<Element.Value>> {
        traverse(\.concurrently)
    }
}

public extension Array where Element: OptionalProtocol {
    var sequenced: Optional<Array<Element.Wrapped>> {
        traverse(\.value)
    }
}

public extension Array where Element: ResultProtocol {
    var sequenced: Result<Array<Element.Success>, Element.Failure> {
        traverse(\.result)
    }
}

public extension Array where Element: ValidationProtocol {
    var sequenced: Validation<Element.Failure, Array<Element.Value>> {
        traverse(\.validation)
    }
}

public extension Array where Element: EitherProtocol {
    var sequenced: Either<Element.L, Array<Element.R>> {
        traverse(\.either)
    }
}