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
            \(raw: access)static func inject<X>(_ effect: any Slingshot.Effect<\(raw: member.family).Family, X>) -> any Slingshot.Effect<\(raw: name), X> {
                Slingshot.Injected<\(raw: name), \(raw: member.family).Family, X>(effect, at: \\Interpreter.\(raw: member.field))
            }
            """
        }
        return [interpreter] + injections
    }
}
