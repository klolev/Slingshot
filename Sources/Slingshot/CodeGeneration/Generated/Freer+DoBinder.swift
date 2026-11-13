#if Macros
public extension Binder {
    /// Binds inside a #do block of type Freer, where a bind can only differ from the block in its `A`.
    func callAsFunction<Family, A, X>(_ m: Freer<Family, X>) -> X where M == Freer<Family, A> {
        fatalError("bind only works inside #do")
    }
}
#endif