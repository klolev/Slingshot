public extension Continuation {
    func map<C>(_ transform: @escaping (Argument) -> C) -> Continuation<Result, C> {
        .init { k in
            run(compose(transform, k))
        }
    }
    
    func replace<C>(with x: C) -> Continuation<Result, C> {
        map(constant(x))
    }
}
