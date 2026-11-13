/// An effect of `Member` lifted into a stack that contains it: it runs with the member's part of the stack's interpreter.
/// `@Effects` builds these; there's no reason to make one by hand.
public struct Injected<Stack: EffectStack, Member: EffectFamily, X>: Effect {
    public typealias Family = Stack
    public typealias Output = X

    let effect: any Effect<Member, X>
    let path: KeyPath<Stack.Interpreter, Member.Interpreter>

    public init(_ effect: any Effect<Member, X>, at path: KeyPath<Stack.Interpreter, Member.Interpreter>) {
        self.effect = effect
        self.path = path
    }

    public func accept(_ interpreter: Stack.Interpreter) async throws -> X {
        try await effect.accept(interpreter[keyPath: path])
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
@attached(member, names: named(Interpreter), named(inject))
public macro Effects() = #externalMacro(module: "SlingshotMacros", type: "EffectsMacro")
#endif
