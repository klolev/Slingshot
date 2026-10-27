extension IO: Pure {
    public static func pure(_ x: Value) -> Self {
        IO { x }
    }
    
}

public extension IO {
    static func ap<O>(_ function: IO<(Value) -> O>) -> (IO<Value>) -> IO<O> {
        { input in
            function.flatMap { f in input.map(f) }
        }
    }

    func apLeft<O>(rhs: IO<O>) -> IO<Value> {
        flatMap { x in
            rhs.map(constant(x))
        }
    }

    func apRight<O>(rhs: IO<O>) -> IO<O> {
        flatMap(constant(rhs))
    }

    func liftA2<B, C>(_ other: IO<B>, _ f: @escaping (Value, B) -> C) -> IO<C> {
        IO<B>.ap(map { a in { b in f(a, b) } })(other)
    }
}
