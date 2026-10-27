public extension IO {
    func replace<C>(with x: C) -> IO<C> {
        map(constant(x))
    }
    
    static func replace<C>(with x: C) -> (IO<Value>) -> IO<C> {
        { items in items.replace(with: x) }
    }
    
    static func map<U>(_ transform: @escaping (Value) -> U) -> (IO<Value>) -> IO<U> {
        { items in items.map(transform) }
    }
}
