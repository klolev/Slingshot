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
///
/// Every bind in a block has the block's own type, so the block's type is inferred into each bind,
/// the way `>>=` ties every statement of a Haskell `do` to one monad:
///
///     let config: Reader<Env, String> = #do { bind in
///         let name = bind(Reader { $0.name })   // `$0` is an `Env`, taken from the block's type
///         return "hello \(name)"
///     }
///
/// In a `Freer` block, bound values can be noncopyable. The block is checked as the straight-line code you write,
/// so a value is consumed at most once. To consume one after a later bind, write `consume name`: `#do` then carries
/// it through the program to that point, since the closures between could only borrow it.
///
///     let keys: Freer<App, Keys> = #do { bind in
///         let session = bind(Pake.start())             // noncopyable
///         let reply = bind(Network.exchange(...))      // session is carried past this bind…
///         return bind(Pake.finish(consume session, reply))   // …to here
///     }
@freestanding(expression)
public macro `do`<M: Bindable & ~Copyable>(_ body: (Binder<M>) -> M.Bound) -> M = #externalMacro(module: "SlingshotMacros", type: "DoMacro")
where M.Bound: ~Copyable

/// `#do` for a whole function: `await` marks each bind, and the return type says what the steps are.
///
///     @Do
///     func page(_ id: ID) -> Freer<App, Page> {
///         let user = await fetchUser(id)
///         let config = await fetchConfig()
///         return render(user, config)
///     }
///
/// It rewrites the body like `#do`: independent binds share a `liftA2`, and a noncopyable value written as
/// `consume name` is carried to that point. The body is only type-checked after the rewrite, so a mistake shows up
/// in the expanded code, not in the lines you wrote.
@attached(body)
public macro Do() = #externalMacro(module: "SlingshotMacros", type: "DoBodyMacro")

/// A type `#do` can bind: `Bound` is the value a bind produces.
public protocol Bindable: ~Copyable {
    associatedtype Bound: ~Copyable
}

/// A `Bindable` type with `flatMap`, so `#do` can bind values that depend on earlier binds.
public protocol DoMonad: Bindable, ~Copyable where Bound: ~Copyable {}

/// Emitted by `#do` before every `flatMap`, so binding through an applicative-only type fails with a clear error.
public func _doMonad<M: DoMonad & ~Copyable>(_ m: consuming M) -> M where M.Bound: ~Copyable {
    m
}

/// Passed to a `#do` block to mark its binds. It can't be created outside `#do`, so `bind` can't be misused elsewhere.
/// `M` is the block's type: a bind takes the same type with only the bound value free,
/// like `>>=`'s `m a -> (a -> m b) -> m b`, so everything else comes from the block.
public struct Binder<M: ~Copyable> {
    init() {}
}

// The overloads that bind each type live in CodeGeneration/Generated/*+DoBinder.swift:
// one per type, because "M with another bound value" needs higher-kinded types.
public extension Binder where M: ~Copyable {
    /// Any other bind is a different type than its block: picked only when no generated overload fits,
    /// so the error names the problem instead of listing every overload.
    @available(*, unavailable, message: "bind takes a value of its #do block's own type; convert it to that type first")
    func callAsFunction<N>(_ m: N) -> N {
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

extension Freer: Bindable where A: ~Copyable {
    public typealias Bound = A
}

extension Optional: DoMonad {}
extension Array: DoMonad {}
extension Result: DoMonad {}
extension Either: DoMonad {}
extension IO: DoMonad {}
extension Reader: DoMonad {}
extension Freer: DoMonad where A: ~Copyable {}
#endif
