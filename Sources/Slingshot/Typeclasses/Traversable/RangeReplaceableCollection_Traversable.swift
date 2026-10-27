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

    func traverse(_ transform: @escaping (Element) -> Promise<Element>) -> Promise<Self> {
        Promise<Element>.traverse(self, transform).map { Self($0) }
    }
}
