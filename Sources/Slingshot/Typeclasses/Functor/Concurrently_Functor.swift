public extension Concurrently {
    func map<C>(_ transform: @escaping @Sendable (Value) -> C) -> Concurrently<C> {
        Concurrently<C> {
            transform(await self._f())
        }
    }
}

// Written by hand rather than from the FunctorExtensions template: `constant` and `flip` return non-Sendable closures.
public extension Concurrently {
    func replace<C>(with x: C) -> Concurrently<C> {
        map { _ in x }
    }

    static func replace<C>(with x: C) -> (Concurrently<Value>) -> Concurrently<C> {
        { items in items.replace(with: x) }
    }

    static func map<U>(_ transform: @escaping @Sendable (Value) -> U) -> (Concurrently<Value>) -> Concurrently<U> {
        { items in items.map(transform) }
    }
}
