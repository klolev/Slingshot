/// An effect of `Member` lifted into a stack that contains it: it runs with the member's part of the stack's interpreter.
/// `@Effects` builds these; there's no reason to make one by hand.
/// An enum, so the effect inside is bound with `switch consume` rather than consumed from a stored property.
public enum Injected<Stack: EffectStack, Member: EffectFamily, X: ~Copyable>: Effect, ~Copyable {
    public typealias Family = Stack
    public typealias Output = X

    case injected(any Effect<Member, X> & ~Copyable, at: KeyPath<Stack.Interpreter, Member.Interpreter>)

    public init(_ effect: consuming any Effect<Member, X> & ~Copyable, at path: KeyPath<Stack.Interpreter, Member.Interpreter>) {
        self = .injected(effect, at: path)
    }

    /// The effect itself, for `@Effects`' `hoist` to inject it into another stack
    public consuming func take() -> any Effect<Member, X> & ~Copyable {
        switch consume self {
        case .injected(let effect, _):
            return effect
        }
    }

    public consuming func accept(_ interpreter: Stack.Interpreter) async throws -> X {
        switch consume self {
        case .injected(let effect, let path):
            return try await runEffect(effect, as: X.self, with: interpreter[keyPath: path])
        }
    }
}

#if Macros
/// Turns an enum holding an `Interpreter` protocol into an effect family: one effect per requirement.
///
///     @EffectFamily
///     enum Keychain {
///         protocol Interpreter {
///             func load(_ key: String) async throws -> Data?
///         }
///     }
///
/// generates, inside `Keychain`:
/// - `Keychain.Operations.Load`, the effect for `load`, and `Keychain.load(_:)`, which performs it in any stack that has the family
///   (the effects are nested in `Operations` so `Log.log`'s effect, `Log`, can't shadow the family's own name)
/// - `Keychain.Has`, the protocol of those stacks: write `Effs: Keychain.Has & Log.Has` to use several families
/// - `Keychain.Family`, the family on its own, a stack of one run by any `Keychain.Interpreter`
@attached(member, names: arbitrary)
public macro EffectFamily() = #externalMacro(module: "SlingshotMacros", type: "EffectFamilyMacro")

/// Turns an enum into a stack of the families it conforms to, run by an `Interpreter` with one interpreter per family.
///
///     @Effects
///     enum App: Keychain.Has, Log.Has {}
///
///     let token: Freer<App, Data?> = Keychain.load("token")
///     try await token.run(with: App.Interpreter(keychain: SystemKeychain(), log: OSLogger()))
///
/// It also generates `hoist(_:into:)`, which moves an `App` program into any stack that has all of App's families.
@attached(member, names: named(Interpreter), named(inject), named(hoist), named(Hoisting))
public macro Effects() = #externalMacro(module: "SlingshotMacros", type: "EffectsMacro")
#endif
