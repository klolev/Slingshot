#if Macros
public extension Binder {
    /// Binds inside a #do block of type Concurrently, where a bind can only differ from the block in its `Value`.
    func callAsFunction<Value: Sendable, X: Sendable>(_ m: Concurrently<X>) -> X where M == Concurrently<Value> {
        fatalError("bind only works inside #do")
    }
}
#endif