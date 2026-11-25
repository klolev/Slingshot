public extension Continuation {
    func flatMap<C>(_ transform: @escaping (Argument) -> Continuation<Result, C>) -> Continuation<Result, C> {
        .init { k in
            run { x in
                transform(x).run(k)
            }
        }
    }
}
