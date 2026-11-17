import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Makes an enum the stack of the families it conforms to: an `Interpreter` with one interpreter per family,
/// and the `inject` each family's `Has` requires, which runs the effect with that family's interpreter.
///
///     @Effects                                        enum App: Keychain.Has, Log.Has {
///     enum App: Keychain.Has, Log.Has {}       →          struct Interpreter { var keychain: ...; var log: ... }
///                                                         static func inject<X>(_ effect: any Effect<Keychain.Family, X>) -> ...
///                                                         static func inject<X>(_ effect: any Effect<Log.Family, X>) -> ...
///                                                     }
///
/// The conformances are the list of families: an extension macro could only add conformances it declares,
/// and each family's `Has` is new, so they're written by hand and the members are derived from them.
public struct EffectsMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let stack = declaration.as(EnumDeclSyntax.self) else {
            throw effectError("@Effects goes on an enum that conforms to the Has of each family it contains", at: node)
        }
        if let generics = stack.genericParameterClause {
            throw effectError("an effect stack can't be generic", at: generics)
        }

        // Every `Family.Has` in the inheritance clause is a member; anything else is left alone
        let members: [(family: String, field: String, syntax: Syntax)] = (stack.inheritanceClause?.inheritedTypes ?? []).compactMap { inherited in
            guard let member = inherited.type.as(MemberTypeSyntax.self), member.name.text == "Has" else { return nil }
            let family = member.baseType.trimmedDescription
            let last = family.split(separator: ".").last.map(String.init) ?? family
            return (family, last.prefix(1).lowercased() + last.dropFirst(), Syntax(inherited))
        }
        guard !members.isEmpty else {
            throw effectError("list the stack's families as conformances: @Effects enum App: Keychain.Has, Log.Has {}", at: stack.name)
        }
        var seen: Set<String> = []
        for member in members where !seen.insert(member.field).inserted {
            throw effectError("two families would both have the interpreter `\(member.field)`: a stack can contain each family once", at: member.syntax)
        }

        let name = stack.name.text
        let access = accessModifier(of: stack)
        let fields = members.map { "\(access)var \($0.field): \($0.family).Family.Interpreter" }.joined(separator: "\n")
        let parameters = members.map { "\($0.field): \($0.family).Family.Interpreter" }.joined(separator: ", ")
        let assignments = members.map { "self.\($0.field) = \($0.field)" }.joined(separator: "\n")
        let interpreter: DeclSyntax = """
        /// Runs a program in \(raw: name): one interpreter per family.
        \(raw: access)struct Interpreter {
            \(raw: fields)

            \(raw: access)init(\(raw: parameters)) {
                \(raw: assignments)
            }
        }
        """
        let injections: [DeclSyntax] = members.map { member in
            """
            \(raw: access)static func inject<X: ~Copyable>(_ effect: consuming any Slingshot.Effect<\(raw: member.family).Family, X> & ~Copyable) -> any Slingshot.Effect<\(raw: name), X> & ~Copyable {
                Slingshot.Injected<\(raw: name), \(raw: member.family).Family, X>(effect, at: \\Interpreter.\(raw: member.field))
            }
            """
        }
        let constraint = members.map { "\($0.family).Has" }.joined(separator: " & ")
        // A type comparison and a move instead of `as?`, which doesn't work on noncopyable values
        let reinjections = members.map { member in
            """
                    if Effect.self == Slingshot.Injected<\(name), \(member.family).Family, X>.self {
                        let injected = Slingshot.unsafeReinterpret(effect, as: Slingshot.Injected<\(name), \(member.family).Family, X>.self)
                        return .perform(Target.inject(injected.take()))
                    }
            """
        }.joined(separator: "\n")
        let hoist: DeclSyntax = """
        /// Moves a program of \(raw: name) into any stack that has all of its families.
        \(raw: access)static func hoist<Target: \(raw: constraint), V: ~Copyable>(_ program: consuming Slingshot.Freer<\(raw: name), V>, into target: Target.Type) -> Slingshot.Freer<Target, V> {
            program.translate(Hoisting<Target>())
        }
        """
        let hoisting: DeclSyntax = """
        /// Each of \(raw: name)'s effects, injected into `Target` instead: \(raw: name)'s effects are all made by its `inject`.
        \(raw: access)struct Hoisting<Target: \(raw: constraint)>: Slingshot.Translation {
            \(raw: access)typealias From = \(raw: name)
            \(raw: access)typealias To = Target

            \(raw: access)func translate<X: ~Copyable>(_ effect: consuming any Slingshot.Effect<\(raw: name), X> & ~Copyable) -> Slingshot.Freer<Target, X> {
                // into a local first: opening a consuming existential parameter directly trips a compiler bug
                let local = consume effect
                return reinjected(local, as: X.self)
            }

            // Opens the effect, so its type can be compared with each family's Injected
            private func reinjected<Effect: Slingshot.Effect & ~Copyable, X: ~Copyable>(_ effect: consuming Effect, as output: X.Type) -> Slingshot.Freer<Target, X>
            where Effect.Output: ~Copyable {
        \(raw: reinjections)
                preconditionFailure("\\(Effect.self) is an effect of \(raw: name) that its inject didn't make")
            }
        }
        """
        return [interpreter] + injections + [hoist, hoisting]
    }
}
