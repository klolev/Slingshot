#if Macros
public extension Binder {
    /// Binds inside a #do block of type Reader, where a bind can only differ from the block in its `Result`.
    func callAsFunction<Dependency, Result, X>(_ m: Reader<Dependency, X>) -> X where M == Reader<Dependency, Result> {
        fatalError("bind only works inside #do")
    }
}
#endif