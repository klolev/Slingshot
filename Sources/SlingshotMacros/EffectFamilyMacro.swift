import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Derives an effect family from the `Interpreter` protocol inside an enum: one effect and one constructor per requirement,
/// the `Has` protocol of the stacks that contain the family, and `Family`, the family as a stack of its own.
///
///     @EffectFamily                                   enum Keychain {
///     enum Keychain {                                     protocol Interpreter { ... }
///         protocol Interpreter {                              enum Operations { struct Load: Operation { let key: String; ... } }
///             func load(_ key: String)          →        protocol Operation: Effect where Family == Keychain.Family {}
///                 async throws -> Data?                   static func load<Effs: Has>(_ key: String) -> Freer<Effs, Data?>
///         }                                               protocol Has: EffectStack { static func inject ... }
///     }                                                   enum Family: Has { typealias Interpreter = any Keychain.Interpreter ... }
///                                                     }
///
/// Everything is nested so every name starts with the one the user wrote. `Family` and `Has` can't be added
/// to `Keychain` itself: an extension macro can only add conformances it declares, and `Keychain.Has` is new.
public struct EffectFamilyMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let family = declaration.as(EnumDeclSyntax.self) else {
            throw effectError("@EffectFamily goes on an enum that declares an Interpreter protocol", at: node)
        }
        if let generics = family.genericParameterClause {
            throw effectError("an effect family can't be generic: Swift doesn't allow the protocols it generates inside a generic type", at: generics)
        }
        let interpreters = family.memberBlock.members.compactMap { $0.decl.as(ProtocolDeclSyntax.self) }.filter { $0.name.text == "Interpreter" }
        guard let interpreter = interpreters.first else {
            throw effectError("declare the family's operations in a `protocol Interpreter` inside the enum", at: family.name)
        }

        let name = family.name.text
        let access = accessModifier(of: family)
        let operations = try interpreter.memberBlock.members.map { try Operation(member: $0) }
        var seen: Set<String> = []
        for operation in operations {
            // Inside an effect, its own name shadows any member of the family with the same name
            guard !["Interpreter", "Operation", "Translation", "Translator"].contains(operation.effectName) else {
                throw effectError("`\(operation.name)` would generate an effect named \(operation.effectName), which the family already uses", at: operation.declaration.name)
            }
            guard operation.name != "translate" else {
                throw effectError("`translate` is the family's translation function: give the requirement another name", at: operation.declaration.name)
            }
            guard seen.insert(operation.effectName).inserted else {
                throw effectError("two requirements would both generate an effect named \(operation.effectName): give them different names", at: operation.declaration.name)
            }
        }

        // An operation named like the family, like `Log.log`, makes an effect named `Log`. Nested in `Operations`,
        // it can't shadow the family's name in the enum's other members, and inside the effect, where it does,
        // nothing spells the family's name: `Family` comes from `Operation` and `Interpreter` from the enum.
        let effects = operations.map { $0.effect(access: access) }.joined(separator: "\n\n")
        let operationsDecl: DeclSyntax = """
        /// One effect per requirement of \(raw: name).Interpreter.
        \(raw: access)enum Operations {
            \(raw: effects)
        }
        """
        let operationProtocol: DeclSyntax = """
        /// What \(raw: name)'s effects have in common: they run with the family's interpreter.
        \(raw: access)protocol Operation: Slingshot.Effect where Family == \(raw: name).Family {
            /// This effect as a program in the translation's target
            func translated<Translating: Translation>(with translation: Translating) -> Slingshot.Freer<Translating.Target, Output>
        }
        """
        let requirements = operations.map { $0.translationRequirement }.joined(separator: "\n")
        let translation: DeclSyntax = """
        /// Translates \(raw: name)'s effects into programs in `Target`: one method per operation of \(raw: name).Interpreter.
        \(raw: access)protocol Translation {
            associatedtype Target: Slingshot.EffectFamily
        
            \(raw: requirements)
        }
        """
        let translator: DeclSyntax = """
        /// A \(raw: name).Translation as the general `Slingshot.Translation`, which `Freer.translate` takes.
        \(raw: access)struct Translator<T: Translation>: Slingshot.Translation {
            \(raw: access)typealias From = Family
            \(raw: access)typealias To = T.Target
        
            \(raw: access)let translation: T
        
            \(raw: access)init(_ translation: T) {
                self.translation = translation
            }
        
            \(raw: access)func translate<X>(_ effect: any Slingshot.Effect<Family, X>) -> Slingshot.Freer<T.Target, X> {
                guard let operation = effect as? any Operation else {
                    preconditionFailure("\\(type(of: effect)) is an effect of \(raw: name) that @EffectFamily didn't generate")
                }
                return translated(operation)
            }
        
            // Opens the operation: its Output is X, which Swift can't see through the existential
            private func translated<O: Operation, X>(_ operation: O) -> Slingshot.Freer<T.Target, X> {
                operation.translated(with: translation) as! Slingshot.Freer<T.Target, X>
            }
        }
        """
        let translate: DeclSyntax = """
        /// Replaces each of \(raw: name)'s effects in `program` by `translation`'s program for it.
        \(raw: access)static func translate<A, T: Translation>(_ program: Slingshot.Freer<Family, A>, with translation: T) -> Slingshot.Freer<T.Target, A> {
            program.translate(Translator(translation))
        }
        """
        let constructors = operations.map { $0.constructor(family: name, access: access) }
        let has: DeclSyntax = """
        /// The stacks that contain this family: \(raw: name)'s constructors work in any of them.
        \(raw: access)protocol Has: Slingshot.EffectStack {
            static func inject<X>(_ effect: any Slingshot.Effect<Family, X>) -> any Slingshot.Effect<Self, X>
        }
        """
        let familyDecl: DeclSyntax = """
        /// The family on its own: a stack of one, run by any \(raw: name).Interpreter.
        \(raw: access)enum Family: Has {
            \(raw: access)typealias Interpreter = any \(raw: name).Interpreter

            \(raw: access)static func inject<X>(_ effect: any Slingshot.Effect<Family, X>) -> any Slingshot.Effect<Family, X> {
                effect
            }
        }
        """
        return [operationsDecl, operationProtocol] + constructors + [has, familyDecl, translation, translator, translate]
    }
}

/// One requirement of an `Interpreter`.
private struct Operation {
    struct Parameter {
        /// The argument label, or nil for `_`
        let label: String?
        let name: String
        let type: String
        let storedType: String
    }

    let declaration: FunctionDeclSyntax
    let parameters: [Parameter]
    let output: String
    let isAsync: Bool
    let isThrowing: Bool

    var name: String { declaration.name.text }

    var effectName: String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
    
    var genericParameters: [String] {
        declaration.genericParameterClause?.parameters.map {
            $0.with(\.trailingComma, nil).trimmedDescription
        } ?? []
    }
    
    var genericClause: String {
        genericParameters.isEmpty ? "" : "<\(genericParameters.joined(separator: ", "))>"
    }
    
    var whereClause: String {
        declaration.genericWhereClause.map { " \($0.trimmedDescription)" } ?? ""
    }


    init(member: MemberBlockItemSyntax) throws {
        guard let function = member.decl.as(FunctionDeclSyntax.self) else {
            throw effectError("an Interpreter can only declare methods: each one becomes an effect", at: member.decl)
        }
        if function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
            throw effectError("effects are performed on an interpreter value, so `\(function.name.text)` can't be static", at: function.name)
        }
        if let generics = function.genericParameterClause {
            for generic in generics.parameters where generic.inheritedType.map(mentionsNoncopyable) ?? false {
                throw noncopyableError(at: generic)
            }

        }
        if let whereClause = function.genericWhereClause, mentionsNoncopyable(whereClause) {
            throw noncopyableError(at: whereClause)
        }

        guard case .identifier = function.name.tokenKind else {
            throw effectError("operators can't be effects: give the requirement a name", at: function.name)
        }

        self.declaration = function
        self.parameters = try function.signature.parameterClause.parameters.map { parameter in
            if parameter.ellipsis != nil {
                throw effectError("variadic parameters aren't supported: take an array instead", at: parameter)
            }
            if let attributed = parameter.type.as(AttributedTypeSyntax.self),
               attributed.specifiers.contains(where: { $0.trimmedDescription == "inout" }) {
                throw effectError("an effect stores its arguments, so they can't be inout", at: parameter.type)
            }
            if let some = parameter.type.tokens(viewMode: .sourceAccurate).first(where: { $0.tokenKind == .keyword(.some) }) {
                throw effectError("an effect stores its arguments, so name the type with a generic parameter instead of `some`", at: some)
            }

            let name = (parameter.secondName ?? parameter.firstName).text
            guard name != "_" else {
                throw effectError("name the parameter: the effect stores it under that name", at: parameter)
            }
            let label = parameter.firstName.text == "_" ? nil : parameter.firstName.text
            return Parameter(label: label, name: name, type: parameter.type.trimmedDescription, storedType: storedType(parameter.type))
        }
        
        let argumentNames = Set(
            function.signature.parameterClause.parameters.flatMap { parameter in
                parameter.type.tokens(viewMode: .sourceAccurate)
                    .compactMap { token -> String? in
                        if case .identifier(let name) = token.tokenKind { return name }
                        return nil
                    }
            }
        )
        
        for generic in function.genericParameterClause?.parameters ?? [] {
            if ["Effs", "Target", "Translating", "Output", "Family"].contains(generic.name.text) {
                throw effectError("`\(generic.name.text)` is used by the generated code: call this generic parameter something else", at: generic.name)
            }
            guard argumentNames.contains(generic.name.text) else {
                throw effectError("`\(generic.name.text)` has to appear in an argument's type: an effect stores its arguments, and its type is inferred from them", at: generic)
            }
        }

        
        self.output = function.signature.returnClause?.type.trimmedDescription ?? "Void"
        self.isAsync = function.signature.effectSpecifiers?.asyncSpecifier != nil
        self.isThrowing = function.signature.effectSpecifiers?.throwsClause != nil
    }

    func effect(access: String) -> String {
        let properties = parameters.map { "\(access)let \($0.name): \($0.storedType)" }.joined(separator: "\n")
        let initParameters = parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        let assignments = parameters.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        let arguments = parameters.map { ($0.label.map { "\($0): " } ?? "") + "self.\($0.name)" }.joined(separator: ", ")
        let call = (isThrowing ? "try " : "") + (isAsync ? "await " : "") + "interpreter.\(name)(\(arguments))"
        // `Family` comes from `Operation`, and `Interpreter` from the family: neither is spelled with the family's name
        return """
        /// Performs `\(name)` with the stack's interpreter.
        \(access)struct \(effectName)\(genericClause): Operation\(whereClause) {
            \(access)typealias Output = \(output)

            \(properties)

            \(access)init(\(initParameters)) {
                \(assignments)
            }

            \(access)func accept(_ interpreter: any Interpreter) async throws -> \(output) {
                \(call)
            }
        
            \(access)func translated<Translating: Translation>(with translation: Translating) -> Slingshot.Freer<Translating.Target, \(output)> {
                translation.\(name)(\(arguments))
            }
        }
        """
    }
    
    /// The requirement as a Translation method: the same signature, returning a program instead of performing it
    var translationRequirement: String {
        let parameters = declaration.signature.parameterClause.parameters.trimmedDescription
        return "func \(name)\(genericClause)(\(parameters)) -> Slingshot.Freer<Target, \(output)>\(whereClause)"
    }

    func constructor(family: String, access: String) -> DeclSyntax {
        let arguments = parameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
        return """
        /// A program that performs `\(raw: name)` in any stack that has \(raw: family).
        \(raw: access)static func \(raw: name)<\(raw: (["Effs: Has"] + genericParameters).joined(separator: ", "))>(\(raw: declaration.signature.parameterClause.parameters.trimmedDescription)) -> Slingshot.Freer<Effs, \(raw: output)>\(raw: whereClause) {
            .perform(Effs.inject(Operations.\(raw: effectName)(\(raw: arguments))))
        }
        """
    }
}

/// The type of a stored property holding a parameter: `@escaping` only applies to parameters
private func storedType(_ type: TypeSyntax) -> String {
    guard let attributed = type.as(AttributedTypeSyntax.self) else { return type.trimmedDescription }
    let attributes = attributed.attributes.filter { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription != "escaping" }
    return attributed.with(\.attributes, attributes).trimmedDescription
}

/// Whether a constraint suppresses Copyable: a `~` token followed by `Copyable`
private func mentionsNoncopyable(_ node: some SyntaxProtocol) -> Bool {
    let tokens = Array(node.tokens(viewMode: .sourceAccurate))
    return zip(tokens, tokens.dropFirst()).contains { $0.text == "~" && $1.text == "Copyable" }
}

private func noncopyableError(at node: some SyntaxProtocol) -> DiagnosticsError {
    effectError("Freer can't carry noncopyable values: a program keeps results in closures, which can't consume what they capture", at: node)
}


/// The access modifier generated members need to be as visible as the enum, with a trailing space
func accessModifier(of declaration: some DeclGroupSyntax) -> String {
    for modifier in declaration.modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public), .keyword(.open):
            return "public "
        case .keyword(.package):
            return "package "
        default:
            continue
        }
    }
    return ""
}

private struct EffectMessage: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "Slingshot", id: "effects") }
    var severity: DiagnosticSeverity { .error }
}

func effectError(_ message: String, at node: some SyntaxProtocol) -> DiagnosticsError {
    DiagnosticsError(diagnostics: [Diagnostic(node: Syntax(node), message: EffectMessage(message: message))])
}
