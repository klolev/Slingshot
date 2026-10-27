// Linear-time traversals of a sequence into an array, one per applicative.
// The generated Traversable conformances build on these, then convert the array to their own container.

public extension Optional {
    static func traverse<S: Sequence>(_ elements: S, _ transform: (S.Element) -> Wrapped?) -> [Wrapped]? {
        elements.reduce(into: []) { result, element in
            if let value = transform(element) {
                result?.append(value)
            } else {
                result = nil
            }
        }
    }
}

public extension Result {
    static func traverse<S: Sequence>(_ elements: S, _ transform: (S.Element) -> Result<Success, Failure>) -> Result<[Success], Failure> {
        var values: [Success] = []
        var firstFailure: Failure?
        for element in elements {
            switch transform(element) {
            case .success(let value):
                values.append(value)
            case .failure(let failure):
                firstFailure = firstFailure ?? failure
            }
        }
        return firstFailure.map(Result<[Success], Failure>.failure) ?? .success(values)
    }
}

public extension Either {
    static func traverse<S: Sequence>(_ elements: S, _ transform: (S.Element) -> Either<L, R>) -> Either<L, [R]> {
        var values: [R] = []
        var firstLeft: L?
        for element in elements {
            switch transform(element) {
            case .right(let value):
                values.append(value)
            case .left(let left):
                firstLeft = firstLeft ?? left
            }
        }
        return firstLeft.map(Either<L, [R]>.left) ?? .right(values)
    }
}

public extension Validation {
    static func traverse<S: Sequence>(_ elements: S, _ transform: (S.Element) -> Validation<Failure, Value>) -> Validation<Failure, [Value]> {
        var values: [Value] = []
        var failures: [Failure] = []
        for element in elements {
            switch transform(element) {
            case .success(let value):
                values.append(value)
            case .failure(let errors):
                failures.append(contentsOf: errors)
            }
        }
        return [Failure].NonEmpty(container: failures).map(Validation<Failure, [Value]>.failure) ?? .success(values)
    }
}

public extension IO {
    static func traverse<S: Sequence>(_ elements: S, _ transform: @escaping (S.Element) -> IO<Value>) -> IO<[Value]> {
        IO<[Value]> {
            var values: [Value] = []
            for element in elements {
                values.append(await transform(element).value)
            }
            return values
        }
    }
}
