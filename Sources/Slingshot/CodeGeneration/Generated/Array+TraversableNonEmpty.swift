public extension Array.NonEmpty {
    func traverse<T>(_ transform: @escaping (Element) -> IO<T>) -> IO<Array<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return IO<T>.traverse(elements, transform).map { Array<T>.NonEmpty(container: Array<T>($0))! }
    }
}

public extension Array.NonEmpty where Element: Sendable {
    func traverse<T>(_ transform: @escaping @Sendable (Element) -> Concurrently<T>) -> Concurrently<Array<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Concurrently<T>.traverse(elements, transform).map { Array<T>.NonEmpty(container: Array<T>($0))! }
    }
}

public extension Array.NonEmpty {
    func traverse<T>(_ transform: @escaping (Element) -> Optional<T>) -> Optional<Array<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Optional<T>.traverse(elements, transform).map { Array<T>.NonEmpty(container: Array<T>($0))! }
    }
}

public extension Array.NonEmpty {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Result<T, Failure>) -> Result<Array<T>.NonEmpty, Failure> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Result<T, Failure>.traverse(elements, transform).map { Array<T>.NonEmpty(container: Array<T>($0))! }
    }
}

public extension Array.NonEmpty {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Validation<Failure, T>) -> Validation<Failure, Array<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Validation<Failure, T>.traverse(elements, transform).map { Array<T>.NonEmpty(container: Array<T>($0))! }
    }
}

public extension Array.NonEmpty {
    func traverse<T, L>(_ transform: @escaping (Element) -> Either<L, T>) -> Either<L, Array<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Either<L, T>.traverse(elements, transform).map { Array<T>.NonEmpty(container: Array<T>($0))! }
    }
}

public extension Array.NonEmpty where Element: Sendable {
    func traverse<T>(_ transform: @escaping @Sendable (Element) -> Concurrently<Optional<T>>) -> Concurrently<Optional<Array<T>.NonEmpty>> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Concurrently<T>.traverse(elements, transform).map { $0.map { Array<T>.NonEmpty(container: Array<T>($0))! } }
    }
}

public extension Array.NonEmpty where Element: Sendable {
    func traverse<T, Failure>(_ transform: @escaping @Sendable (Element) -> Concurrently<Result<T, Failure>>) -> Concurrently<Result<Array<T>.NonEmpty, Failure>> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Concurrently<T>.traverse(elements, transform).map { $0.map { Array<T>.NonEmpty(container: Array<T>($0))! } }
    }
}

public extension Array.NonEmpty where Element: Sendable {
    func traverse<T, L>(_ transform: @escaping @Sendable (Element) -> Concurrently<Either<L, T>>) -> Concurrently<Either<L, Array<T>.NonEmpty>> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Concurrently<T>.traverse(elements, transform).map { $0.map { Array<T>.NonEmpty(container: Array<T>($0))! } }
    }
}