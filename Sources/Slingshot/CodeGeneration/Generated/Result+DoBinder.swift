#if Macros
public extension Binder {
    /// Binds inside a #do block of type Result, where a bind can only differ from the block in its `Success`.
    func callAsFunction<Success, Failure, X>(_ m: Result<X, Failure>) -> X where M == Result<Success, Failure> {
        fatalError("bind only works inside #do")
    }
}
#endif