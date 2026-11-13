#if Macros
public extension Binder {
    /// Binds inside a #do block of type Either, where a bind can only differ from the block in its `R`.
    func callAsFunction<L, R, X>(_ m: Either<L, X>) -> X where M == Either<L, R> {
        fatalError("bind only works inside #do")
    }
}
#endif