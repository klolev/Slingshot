#if Macros
public extension Binder {
    /// Binds inside a #do block of type IO, where a bind can only differ from the block in its `Value`.
    func callAsFunction<Value, X>(_ m: IO<X>) -> X where M == IO<Value> {
        fatalError("bind only works inside #do")
    }
}
#endif