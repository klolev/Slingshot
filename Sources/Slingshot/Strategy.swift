/// Describes how a `Concurrently` traversal schedules its children, in the spirit of Haskell's evaluation strategies.
/// A strategy only changes how the work runs, never the result: `x.using(s).value` always equals `x.value`.
///
///     let posts = await users.traverse { user in user.posts.traverse(fetch) }
///         .using(.parallel(width: 4).then(.sequential))
///         .value
public struct Strategy: Sendable {
    /// How many children of one traversal run at a time; `nil` runs them all at once
    public var width: Int?
    /// Passed to `addTask(priority:)`
    public var priority: TaskPriority?
    /// Passed to `addTask(name:)` where the runtime supports task names
    public var name: String?
    /// Passed to `addTask(executorPreference:)`
    public var executor: (any TaskExecutor)?

    private var innerStorage: Inner?

    public init(width: Int? = nil, priority: TaskPriority? = nil, name: String? = nil) {
        self.width = width
        self.priority = priority
        self.name = name
    }

    /// The strategy for traversals nested inside this one's children; defaults to this strategy
    public var inner: Strategy {
        get { innerStorage?.strategy ?? self }
        set { innerStorage = Inner(strategy: newValue) }
    }

    // A struct can't contain itself directly
    private final class Inner: Sendable {
        let strategy: Strategy

        init(strategy: Strategy) {
            self.strategy = strategy
        }
    }
}

public extension Strategy {
    /// Runs every child at the same time
    static let parallel = Strategy()

    /// Runs one child at a time, in order
    static let sequential = Strategy(width: 1)

    static func parallel(width: Int) -> Strategy {
        Strategy(width: width)
    }

    func then(_ inner: Strategy) -> Strategy {
        var copy = self
        copy.inner = inner
        return copy
    }

    func priority(_ priority: TaskPriority?) -> Strategy {
        var copy = self
        copy.priority = priority
        return copy
    }

    func named(_ name: String?) -> Strategy {
        var copy = self
        copy.name = name
        return copy
    }

    func executor(_ executor: (any TaskExecutor)?) -> Strategy {
        var copy = self
        copy.executor = executor
        return copy
    }
}

public extension Strategy {
    /// The strategy traversals use while running; set it with `Concurrently.using(_:)`
    @TaskLocal static var current: Strategy = .parallel
}

extension Strategy {
    /// Adds `operation` to `group` with this strategy's task options, running it under `inner`.
    func addTask<T: Sendable>(to group: inout TaskGroup<T>, _ operation: @escaping @Sendable () async -> T) {
        let inner = inner
        let child: @Sendable () async -> T = {
            await Strategy.$current.withValue(inner) { await operation() }
        }
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            group.addTask(name: name, executorPreference: executor, priority: priority, operation: child)
        } else {
            group.addTask(executorPreference: executor, priority: priority, operation: child)
        }
    }
}

extension Strategy {
    /// Starts `operation` as an unstructured task with this strategy's task options, running it under `inner`.
    /// For work that has to outlive a task group's scope, like the elements of a stream.
    func makeTask(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let inner = inner
        let child: @Sendable () async -> Void = {
            await Strategy.$current.withValue(inner) { await operation() }
        }
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            return Task(name: name, executorPreference: executor, priority: priority, operation: child)
        } else {
            return Task(executorPreference: executor, priority: priority, operation: child)
        }
    }
}

public extension Concurrently {
    /// Runs this computation's traversals with `strategy`.
    func using(_ strategy: Strategy) -> Concurrently<Value> {
        Concurrently {
            await Strategy.$current.withValue(strategy) { await self.value }
        }
    }
}
