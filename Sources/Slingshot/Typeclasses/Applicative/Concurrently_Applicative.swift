extension Concurrently: Pure {
    public static func pure(_ x: Value) -> Self {
        Concurrently { x }
    }
}

public extension Concurrently {
    static func ap<O>(_ function: Concurrently<@Sendable (Value) -> O>) -> (Concurrently<Value>) -> Concurrently<O> {
        { input in
            function.liftA2(input) { f, x in f(x) }
        }
    }

    func apLeft<O>(rhs: Concurrently<O>) -> Concurrently<Value> {
        liftA2(rhs) { x, _ in x }
    }

    func apRight<O>(rhs: Concurrently<O>) -> Concurrently<O> {
        liftA2(rhs) { _, y in y }
    }

    /// Runs both computations at the same time and combines their results.
    func liftA2<B, C>(_ other: Concurrently<B>, _ f: @escaping @Sendable (Value, B) -> C) -> Concurrently<C> {
        Concurrently<C> {
            async let a = self.value
            async let b = other.value
            return await f(a, b)
        }
    }
}
