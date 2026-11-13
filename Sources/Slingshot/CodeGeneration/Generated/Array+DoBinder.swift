#if Macros
public extension Binder {
    /// Binds inside a #do block of type Array, where a bind can only differ from the block in its `Element`.
    func callAsFunction<Element, X>(_ m: Array<X>) -> X where M == Array<Element> {
        fatalError("bind only works inside #do")
    }
}
#endif