#if Macros
public extension Binder {
    /// Binds inside a #do block of type Continuation, where a bind can only differ from the block in its `Argument`.
    func callAsFunction<Result, Argument, X>(_ m: Continuation<Result, X>) -> X where M == Continuation<Result, Argument> {
        fatalError("bind only works inside #do")
    }
}
#endif