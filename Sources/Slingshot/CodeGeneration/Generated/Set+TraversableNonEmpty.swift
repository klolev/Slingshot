public extension Set.NonEmpty {
    func traverse<T>(_ transform: @escaping (Element) -> IO<T>) -> IO<Set<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return IO<T>.traverse(elements, transform).map { Set<T>.NonEmpty(container: Set<T>($0))! }
    }
}

public extension Set.NonEmpty {
    func traverse<T>(_ transform: @escaping (Element) -> Optional<T>) -> Optional<Set<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Optional<T>.traverse(elements, transform).map { Set<T>.NonEmpty(container: Set<T>($0))! }
    }
}

public extension Set.NonEmpty {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Result<T, Failure>) -> Result<Set<T>.NonEmpty, Failure> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Result<T, Failure>.traverse(elements, transform).map { Set<T>.NonEmpty(container: Set<T>($0))! }
    }
}

public extension Set.NonEmpty {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Validation<Failure, T>) -> Validation<Failure, Set<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Validation<Failure, T>.traverse(elements, transform).map { Set<T>.NonEmpty(container: Set<T>($0))! }
    }
}

public extension Set.NonEmpty {
    func traverse<T, L>(_ transform: @escaping (Element) -> Either<L, T>) -> Either<L, Set<T>.NonEmpty> {
        let elements = container.isEmpty ? [first] : Array(container)
        // A non-empty input always yields a non-empty output
        return Either<L, T>.traverse(elements, transform).map { Set<T>.NonEmpty(container: Set<T>($0))! }
    }
}