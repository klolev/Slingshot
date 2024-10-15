public extension Promise {
    func replace<C>(with x: C) -> Promise<C> {
        map(constant(x))
    }
    
    static func replace<C>(with x: C) -> (Promise<Value>) -> Promise<C> {
        flip(Promise<Value>.replace(with:))(x)
    }
    
    static func map<U>(_ transform: @escaping (Value) -> U) -> (Promise<Value>) -> Promise<U> {
        { items in items.map(transform) }
    }
}
