#if Macros
public extension Binder {
    /// Binds inside a #do block of type Validation, where a bind can only differ from the block in its `Value`.
    func callAsFunction<Failure, Value, X>(_ m: Validation<Failure, X>) -> X where M == Validation<Failure, Value> {
        fatalError("bind only works inside #do")
    }
}
#endif