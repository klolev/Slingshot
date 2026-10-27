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

    // `any TaskExecutor` only exists from macOS 15 / iOS 18, so it's stored type-erased
    private var executorStorage: (any Sendable)?
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

    /// Passed to `addTask(executorPreference:)`
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    public var executor: (any TaskExecutor)? {
        get { executorStorage as? any TaskExecutor }
        set { executorStorage = newValue }
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

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
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
        } else if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
            group.addTask(executorPreference: executor, priority: priority, operation: child)
        } else {
            group.addTask(priority: priority, operation: child)
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
