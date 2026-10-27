// Traversals that keep the element type, for collections that can't be rebuilt around a new one (e.g. String).

public extension RangeReplaceableCollection {
    func traverse(_ transform: @escaping (Element) -> Optional<Element>) -> Optional<Self> {
        Optional<Element>.traverse(self, transform).map { Self($0) }
    }

    func traverse<Failure>(_ transform: @escaping (Element) -> Result<Element, Failure>) -> Result<Self, Failure> {
        Result<Element, Failure>.traverse(self, transform).map { Self($0) }
    }

    func traverse<Failure>(_ transform: @escaping (Element) -> Validation<Failure, Element>) -> Validation<Failure, Self> {
        Validation<Failure, Element>.traverse(self, transform).map { Self($0) }
    }

    func traverse<L>(_ transform: @escaping (Element) -> Either<L, Element>) -> Either<L, Self> {
        Either<L, Element>.traverse(self, transform).map { Self($0) }
    }

    func traverse(_ transform: @escaping (Element) -> IO<Element>) -> IO<Self> {
        IO<Element>.traverse(self, transform).map { Self($0) }
    }
}

public extension RangeReplaceableCollection where Self: Sendable, Element: Sendable {
    func traverse(_ transform: @escaping @Sendable (Element) -> Concurrently<Element>) -> Concurrently<Self> {
        Concurrently<Element>.traverse(self, transform).map { Self($0) }
    }

    func traverse(_ transform: @escaping @Sendable (Element) -> Concurrently<Optional<Element>>) -> Concurrently<Optional<Self>> {
        Concurrently<Element>.traverse(self, transform).map { $0.map { Self($0) } }
    }

    func traverse<Failure>(_ transform: @escaping @Sendable (Element) -> Concurrently<Result<Element, Failure>>) -> Concurrently<Result<Self, Failure>> {
        Concurrently<Element>.traverse(self, transform).map { $0.map { Self($0) } }
    }

    func traverse<L>(_ transform: @escaping @Sendable (Element) -> Concurrently<Either<L, Element>>) -> Concurrently<Either<L, Self>> {
        Concurrently<Element>.traverse(self, transform).map { $0.map { Self($0) } }
    }
}
