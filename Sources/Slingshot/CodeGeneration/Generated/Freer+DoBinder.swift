#if Macros
public extension Binder where M: ~Copyable {
    /// Binds inside a #do block of type Freer, where a bind can only differ from the block in its `A`.
    func callAsFunction<Family, A: ~Copyable, X: ~Copyable>(_ m: consuming Freer<Family, X>) -> X where M == Freer<Family, A> {
        fatalError("bind only works inside #do")
    }
}
#endif