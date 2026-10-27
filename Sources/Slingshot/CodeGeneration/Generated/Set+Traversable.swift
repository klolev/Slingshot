public extension Set {
    func traverse<T>(_ transform: @escaping (Element) -> IO<T>) -> IO<Set<T>> {
        IO<T>.traverse(self, transform).map { Set<T>($0) }
    }
}

public extension Set {
    func traverse<T>(_ transform: @escaping (Element) -> Optional<T>) -> Optional<Set<T>> {
        Optional<T>.traverse(self, transform).map { Set<T>($0) }
    }
}

public extension Set {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Result<T, Failure>) -> Result<Set<T>, Failure> {
        Result<T, Failure>.traverse(self, transform).map { Set<T>($0) }
    }
}

public extension Set {
    func traverse<T, Failure>(_ transform: @escaping (Element) -> Validation<Failure, T>) -> Validation<Failure, Set<T>> {
        Validation<Failure, T>.traverse(self, transform).map { Set<T>($0) }
    }
}

public extension Set {
    func traverse<T, L>(_ transform: @escaping (Element) -> Either<L, T>) -> Either<L, Set<T>> {
        Either<L, T>.traverse(self, transform).map { Set<T>($0) }
    }
}

public extension Set where Element: IOProtocol, Element.Value: Hashable {
    var sequenced: IO<Set<Element.Value>> {
        traverse(\.io)
    }
}

public extension Set where Element: OptionalProtocol, Element.Wrapped: Hashable {
    var sequenced: Optional<Set<Element.Wrapped>> {
        traverse(\.value)
    }
}

public extension Set where Element: ResultProtocol, Element.Success: Hashable {
    var sequenced: Result<Set<Element.Success>, Element.Failure> {
        traverse(\.result)
    }
}

public extension Set where Element: ValidationProtocol, Element.Value: Hashable {
    var sequenced: Validation<Element.Failure, Set<Element.Value>> {
        traverse(\.validation)
    }
}

public extension Set where Element: EitherProtocol, Element.R: Hashable {
    var sequenced: Either<Element.L, Set<Element.R>> {
        traverse(\.either)
    }
}