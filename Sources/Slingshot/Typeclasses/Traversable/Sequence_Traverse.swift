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

public extension Concurrently {
    /// Runs the transforms as `Strategy.current` allows; the results keep the order of `elements`.
    static func traverse<S: Sequence>(_ elements: S, _ transform: @escaping @Sendable (S.Element) -> Concurrently<Value>) -> Concurrently<[Value]> where S.Element: Sendable {
        traverse(elements) { element in
            transform(element).map(Either<Never, Value>.right)
        }
        .map { result in
            switch result {
            case .right(let values): values
            }
        }
    }
}

// Traversals into Concurrently composed with a short-circuiting applicative.
// They give the same result as traversing then sequencing, but cancel the work that can no longer change it.

public extension Concurrently {
    /// Runs the transforms as `Strategy.current` allows and returns the first `left` in input order.
    /// A `left` doesn't decide the result on its own, since an earlier element could still fail,
    /// so the remaining work is cancelled, and nothing new is started, once every element before it has finished.
    static func traverse<S: Sequence, L: Sendable>(_ elements: S, _ transform: @escaping @Sendable (S.Element) -> Concurrently<Either<L, Value>>) -> Concurrently<Either<L, [Value]>> where S.Element: Sendable {
        let elements = Array(elements)
        return Concurrently<Either<L, [Value]>> {
            let strategy = Strategy.current
            return await withTaskGroup(of: (Int, Either<L, Value>).self) { group in
                func start(_ index: Int, in group: inout TaskGroup<(Int, Either<L, Value>)>) {
                    let element = elements[index]
                    strategy.addTask(to: &group) { (index, await transform(element).value) }
                }
                let width = max(strategy.width ?? elements.count, 1)
                var started = 0
                while started < min(width, elements.count) {
                    start(started, in: &group)
                    started += 1
                }
                var values = [Value?](repeating: nil, count: elements.count)
                var finished = [Bool](repeating: false, count: elements.count)
                // Every element before this index has finished
                var settled = 0
                var firstLeft: (index: Int, value: L)?
                while let (index, result) = await group.next() {
                    finished[index] = true
                    while settled < finished.count && finished[settled] {
                        settled += 1
                    }
                    switch result {
                    case .right(let value):
                        values[index] = value
                    case .left(let left):
                        if index < firstLeft?.index ?? .max {
                            firstLeft = (index, left)
                        }
                    }
                    if let firstLeft, settled >= firstLeft.index {
                        group.cancelAll()
                        return .left(firstLeft.value)
                    }
                    if started < elements.count {
                        start(started, in: &group)
                        started += 1
                    }
                }
                // No element failed, so every slot is filled
                return .right(values.map { $0! })
            }
        }
    }

    static func traverse<S: Sequence, Failure>(_ elements: S, _ transform: @escaping @Sendable (S.Element) -> Concurrently<Result<Value, Failure>>) -> Concurrently<Result<[Value], Failure>> where S.Element: Sendable {
        traverse(elements) { element in
            transform(element).map { result -> Either<Failure, Value> in
                switch result {
                case .success(let value): .right(value)
                case .failure(let failure): .left(failure)
                }
            }
        }
        .map(\.result)
    }

    static func traverse<S: Sequence>(_ elements: S, _ transform: @escaping @Sendable (S.Element) -> Concurrently<Value?>) -> Concurrently<[Value]?> where S.Element: Sendable {
        traverse(elements) { element in
            transform(element).map { value -> Either<Void, Value> in
                value.map(Either.right) ?? .left(())
            }
        }
        .map(\.right)
    }
}
