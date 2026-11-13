#if Macros
public extension Binder {
    /// Binds inside a #do block of type Optional, where a bind can only differ from the block in its `Wrapped`.
    func callAsFunction<Wrapped, Arg: OptionalProtocol>(_ m: Arg) -> Arg.Wrapped where M == Optional<Wrapped> {
        fatalError("bind only works inside #do")
    }
}
#endif