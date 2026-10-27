/// A type that can be provided through `Ambient`. Its default is what `Ambient.ask` returns when nothing was provided,
/// so asking always succeeds. Two values of the same type share a slot: wrap one in its own type to keep them apart.
public protocol AmbientValue: Sendable {
    static var defaultValue: Self { get }
}

/// `Reader`'s environment as a task-local: `provide` a value, and code anywhere inside, including across `await`
/// and in child tasks, can `ask` for it without it being passed down as a parameter.
///
///     await Ambient.provide(Config(baseURL: url)) {
///         await app()   // anywhere inside: Ambient.ask(Config.self).baseURL
///     }
///
/// Values are keyed by type, so a value provided further in shadows an outer one of the same type.
/// They're Sendable because child tasks can read them; non-Sendable dependencies stay with `Reader.execute(with:)`.
public enum Ambient {
    @TaskLocal private static var values: [ObjectIdentifier: any Sendable] = [:]

    public static func provide<T: AmbientValue, R>(_ value: T, _ body: () throws -> R) rethrows -> R {
        try $values.withValue(adding(value), operation: body)
    }

    nonisolated(nonsending) public static func provide<T: AmbientValue, R>(_ value: T, _ body: nonisolated(nonsending) () async throws -> R) async rethrows -> R {
        try await $values.withValue(adding(value), operation: body)
    }

    /// The innermost provided `T`, or its default when none was provided
    public static func ask<T: AmbientValue>(_ type: T.Type = T.self) -> T {
        values[ObjectIdentifier(type)] as? T ?? T.defaultValue
    }

    /// Runs `body` with the provided `T` replaced by `transform` of it, like `Reader`'s `local`.
    public static func local<T: AmbientValue, R>(_ type: T.Type = T.self, _ transform: (T) -> T, _ body: () throws -> R) rethrows -> R {
        try provide(transform(ask(type)), body)
    }

    nonisolated(nonsending) public static func local<T: AmbientValue, R>(_ type: T.Type = T.self, _ transform: (T) -> T, _ body: nonisolated(nonsending) () async throws -> R) async rethrows -> R {
        try await provide(transform(ask(type)), body)
    }

    private static func adding<T: AmbientValue>(_ value: T) -> [ObjectIdentifier: any Sendable] {
        var updated = values
        updated[ObjectIdentifier(T.self)] = value
        return updated
    }
}

public extension Reader where Dependency: AmbientValue {
    /// A reader whose body asks for its dependency with `Ambient.ask` instead of taking it as a parameter.
    static func ambient(_ body: @escaping () -> Result) -> Reader<Dependency, Result> {
        Reader { dependency in
            Ambient.provide(dependency, body)
        }
    }

    /// Runs the reader with the ambient dependency: the one from `Ambient.provide`, or its default.
    func execute() -> Result {
        execute(with: Ambient.ask(Dependency.self))
    }
}
