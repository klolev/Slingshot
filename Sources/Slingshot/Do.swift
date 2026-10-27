#if Macros
/// Do-notation for any type with `map`, `flatMap` and `liftA2`.
/// Name the closure's parameter, then bind with `let x = bind(m)`; the block's `return` is the final value.
///
///     let page: Concurrently<Page> = #do { bind in
///         let user = bind(fetchUser(id))
///         let config = bind(fetchConfig())   // doesn't use `user`, so it runs alongside it
///         return render(user, config)
///     }
///
/// Like Haskell's ApplicativeDo, binds that don't use each other's names are combined with `liftA2`
/// rather than `flatMap`: they run concurrently in `Concurrently` and collect every error in `Validation`.
/// Only a bind that uses an earlier one needs a monad, a type conforming to `DoMonad`.
/// Binds must be top-level `let`/`var` statements, or a final `return bind(m)`.
///
/// Keep plain statements free of side effects, like Haskell's `let`: effects belong in binds.
/// Statements before the first bind run when the value is built, the rest when it runs,
/// and statements between independent binds move after them.
@freestanding(expression)
public macro `do`<M: Bindable>(_ body: (Binder) -> M.Bound) -> M = #externalMacro(module: "SlingshotMacros", type: "DoMacro")

/// A type `#do` can bind: `Bound` is the value a bind produces.
public protocol Bindable {
    associatedtype Bound
}

/// A `Bindable` type with `flatMap`, so `#do` can bind values that depend on earlier binds.
public protocol DoMonad: Bindable {}

/// Emitted by `#do` before every `flatMap`, so binding through an applicative-only type fails with a clear error.
public func _doMonad<M: DoMonad>(_ m: M) -> M {
    m
}

/// Passed to a `#do` block to mark its binds. It can't be created outside `#do`, so `bind` can't be misused elsewhere.
public struct Binder {
    init() {}

    /// Only for type checking: `#do` rewrites every call before the code runs.
    public func callAsFunction<M: Bindable>(_ m: M) -> M.Bound {
        fatalError("bind only works inside #do")
    }
}

extension Optional: Bindable {
    public typealias Bound = Wrapped
}

extension Array: Bindable {
    public typealias Bound = Element
}

extension Result: Bindable {
    public typealias Bound = Success
}

extension Either: Bindable {
    public typealias Bound = R
}

extension Validation: Bindable {
    public typealias Bound = Value
}

extension IO: Bindable {
    public typealias Bound = Value
}

extension Concurrently: Bindable {
    public typealias Bound = Value
}

extension Reader: Bindable {
    public typealias Bound = Result
}

extension Optional: DoMonad {}
extension Array: DoMonad {}
extension Result: DoMonad {}
extension Either: DoMonad {}
extension IO: DoMonad {}
extension Reader: DoMonad {}
#endif
