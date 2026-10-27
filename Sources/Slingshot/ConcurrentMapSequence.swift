public extension AsyncSequence where Element: Sendable {
    /// Runs `transform`'s work for each element as `strategy` allows: at most `width` elements are outstanding,
    /// counting results not yet consumed, so the stream is read only as fast as results are used.
    /// Results come in input order when `ordered`, otherwise as they finish. It fails only as the stream does.
    ///
    ///     for await page in urls.mapConcurrently(.parallel(width: 4)) { url in fetch(url) } { … }
    ///
    /// With no width, every element starts as soon as it arrives, so an endless stream is read without limit.
    /// Stopping the iteration early cancels the work still running.
    func mapConcurrently<T: Sendable>(_ strategy: Strategy,
                                      ordered: Bool = true,
                                      _ transform: @escaping @Sendable (Element) -> Concurrently<T>) -> ConcurrentMapSequence<Self, T> {
        ConcurrentMapSequence(base: self, strategy: strategy, ordered: ordered, transform: transform)
    }
}

// Traversals run every element's work as `Strategy.current` allows and collect the results in order.
// The outer Result is the stream's own failure; streams that can't fail get the overloads without it further down.
// The short-circuiting ones run ordered, so the first failure to arrive is the first in input order; returning then
// stops reading the stream and cancels the work still running, which finishes in the background.

public extension AsyncSequence where Self: Sendable, Element: Sendable {
    func traverse<T: Sendable>(_ transform: @escaping @Sendable (Element) -> Concurrently<T>) -> Concurrently<Result<[T], Failure>> {
        traverse { element in
            transform(element).map(Either<Never, T>.right)
        }
        .map { result in
            result.map { either in
                switch either {
                case .right(let values): values
                }
            }
        }
    }

    func traverse<T: Sendable, L: Sendable>(_ transform: @escaping @Sendable (Element) -> Concurrently<Either<L, T>>) -> Concurrently<Result<Either<L, [T]>, Failure>> {
        Concurrently {
            do throws(Failure) {
                var values: [T] = []
                for try await result in self.mapConcurrently(Strategy.current, transform) {
                    switch result {
                    case .right(let value):
                        values.append(value)
                    case .left(let left):
                        return .success(.left(left))
                    }
                }
                return .success(.right(values))
            } catch {
                return .failure(error)
            }
        }
    }

    func traverse<T: Sendable, ElementFailure>(_ transform: @escaping @Sendable (Element) -> Concurrently<Result<T, ElementFailure>>) -> Concurrently<Result<Result<[T], ElementFailure>, Failure>> {
        traverse { element in
            transform(element).map { result -> Either<ElementFailure, T> in
                switch result {
                case .success(let value): .right(value)
                case .failure(let failure): .left(failure)
                }
            }
        }
        .map { $0.map(\.result) }
    }

    func traverse<T: Sendable>(_ transform: @escaping @Sendable (Element) -> Concurrently<T?>) -> Concurrently<Result<[T]?, Failure>> {
        traverse { element in
            transform(element).map { value -> Either<Void, T> in
                value.map(Either.right) ?? .left(())
            }
        }
        .map { $0.map(\.right) }
    }
}

// More constrained, so these are picked for streams that can't fail; `get()` on a Result that can't fail doesn't throw

public extension AsyncSequence where Self: Sendable, Element: Sendable, Failure == Never {
    func traverse<T: Sendable>(_ transform: @escaping @Sendable (Element) -> Concurrently<T>) -> Concurrently<[T]> {
        traverse(transform).map { (result: Result<[T], Never>) in result.get() }
    }

    func traverse<T: Sendable, L: Sendable>(_ transform: @escaping @Sendable (Element) -> Concurrently<Either<L, T>>) -> Concurrently<Either<L, [T]>> {
        traverse(transform).map { (result: Result<Either<L, [T]>, Never>) in result.get() }
    }

    func traverse<T: Sendable, ElementFailure>(_ transform: @escaping @Sendable (Element) -> Concurrently<Result<T, ElementFailure>>) -> Concurrently<Result<[T], ElementFailure>> {
        traverse(transform).map { (result: Result<Result<[T], ElementFailure>, Never>) in result.get() }
    }

    func traverse<T: Sendable>(_ transform: @escaping @Sendable (Element) -> Concurrently<T?>) -> Concurrently<[T]?> {
        traverse(transform).map { (result: Result<[T]?, Never>) in result.get() }
    }
}

public struct ConcurrentMapSequence<Base: AsyncSequence, T: Sendable>: AsyncSequence where Base.Element: Sendable {
    public typealias Element = T
    public typealias Failure = Base.Failure

    let base: Base
    let strategy: Strategy
    let ordered: Bool
    let transform: @Sendable (Base.Element) -> Concurrently<T>

    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator(), window: TaskWindow(strategy: strategy, ordered: ordered), transform: transform)
    }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Failure = Base.Failure

        var base: Base.AsyncIterator
        var baseFinished = false
        let window: TaskWindow<T>
        let transform: @Sendable (Base.Element) -> Concurrently<T>

        public mutating func next(isolation actor: isolated (any Actor)?) async throws(Base.Failure) -> T? {
            while window.hasRoom, !baseFinished {
                guard let element = try await base.next(isolation: actor) else {
                    baseFinished = true
                    break
                }
                let transform = transform
                window.start { await transform(element).value }
            }
            return await window.next()
        }

        public mutating func next() async throws(Base.Failure) -> T? {
            try await next(isolation: nil)
        }
    }
}

extension ConcurrentMapSequence: Sendable where Base: Sendable {}

/// Runs work as unstructured tasks, at most `strategy.width` outstanding at a time,
/// and hands the results back in input order or as they finish. Dropping it cancels what's still running.
final class TaskWindow<T: Sendable> {
    private let strategy: Strategy
    private let ordered: Bool
    private var results: AsyncStream<(Int, T)>.Iterator
    private let continuation: AsyncStream<(Int, T)>.Continuation
    private var tasks: [Int: Task<Void, Never>] = [:]
    /// Finished results waiting for the ones before them, when ordered
    private var buffered: [Int: T] = [:]
    private var started = 0
    private var returned = 0

    init(strategy: Strategy, ordered: Bool) {
        self.strategy = strategy
        self.ordered = ordered
        let (stream, continuation) = AsyncStream.makeStream(of: (Int, T).self)
        self.results = stream.makeAsyncIterator()
        self.continuation = continuation
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
        continuation.finish()
    }

    var hasRoom: Bool {
        strategy.width.map { started - returned < max($0, 1) } ?? true
    }

    func start(_ operation: @escaping @Sendable () async -> T) {
        let index = started
        let continuation = continuation
        let task = strategy.makeTask {
            continuation.yield((index, await operation()))
        }
        // Unstructured tasks don't inherit cancellation, so pass it on by hand
        if Task.isCancelled {
            task.cancel()
        }
        tasks[index] = task
        started += 1
    }

    /// The next result, or `nil` once nothing is outstanding. Runs on the caller's actor, like the iterator using it.
    nonisolated(nonsending) func next() async -> T? {
        while started > returned {
            if ordered, let value = buffered.removeValue(forKey: returned) {
                returned += 1
                return value
            }
            let running = Array(tasks.values)
            let result = await withTaskCancellationHandler {
                await results.next(isolation: #isolation)
            } onCancel: {
                for task in running {
                    task.cancel()
                }
            }
            guard let (index, value) = result else {
                return nil
            }
            tasks[index] = nil
            if ordered {
                buffered[index] = value
            } else {
                returned += 1
                return value
            }
        }
        return nil
    }
}
