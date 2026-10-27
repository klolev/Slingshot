import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Rewrites a `#do` block into `map`, `flatMap` and `liftA2`, the way Haskell desugars `do` with ApplicativeDo.
///
///     #do { bind in                         { return (fetchUser(id)).liftA2(fetchConfig()) { ($0, $1) }.map { bound in
///         let user = bind(fetchUser(id))         let user = bound.0
///         let config = bind(fetchConfig())  →    let config = bound.1
///         return render(user, config)            return render(user, config)
///     }                                       } }()
public struct DoMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> ExprSyntax {
        guard let closure = node.trailingClosure ?? node.arguments.first?.expression.as(ClosureExprSyntax.self) else {
            throw error("#do takes a closure: #do { bind in ... }", at: node)
        }
        guard let binder = binderName(of: closure) else {
            throw error("name the closure's parameter, then bind with it: #do { bind in let x = bind(m) ... }", at: closure)
        }
        // Nested blocks are expanded here first: Swift won't expand a macro whose expansion contains itself,
        // and once they're expanded, their binds can't be mistaken for this block's
        let expander = NestedDoExpander(context: context)
        let body = expander.rewrite(closure.statements)
        if let error = expander.errors.first {
            throw error
        }
        guard let body = body.as(CodeBlockItemListSyntax.self) else {
            throw error("#do couldn't expand the blocks nested in this one", at: closure)
        }
        let statements = try body.map { try Statement(classifying: $0, binder: binder) }

        guard statements.contains(where: \.isBind) else {
            return "\(raw: ".pure({\n\(body.trimmedDescription)\n}())")"
        }
        if let last = statements.last, case .bind(let bind) = last {
            throw error("#do must end with a return", at: bind.statement)
        }
        var names = Names()
        return "\(raw: "{\n\(desugar(statements[...], names: &names))\n}()")"
    }

    /// Emits `statements` as a closure body: plain statements as written, binds as calls whose closures hold the rest.
    private static func desugar(_ statements: ArraySlice<Statement>, names: inout Names) -> String {
        guard let first = statements.firstIndex(where: \.isBind) else {
            return statements.map(\.source).joined(separator: "\n")
        }
        var lines = statements[..<first].map(\.source)

        if case .returnBind(let expression) = statements[first] {
            // Anything after a return can't run, so it's dropped
            lines.append("return \(expression.trimmedDescription)")
            return lines.joined(separator: "\n")
        }

        // Binds that don't use each other's names are independent, so they're combined with liftA2.
        // Plain statements between them move into the continuation, after the binds, unless a later bind
        // mentions a name they mention, or they could return early and skip the binds after them.
        var segment: [Bind] = []
        var deferred: [Statement] = []
        var pending: [Statement] = []
        var blocked: Set<String> = []
        var next = first
        scan: while next < statements.endIndex {
            switch statements[next] {
            case .bind(let bind):
                guard segment.isEmpty || bind.expression.identifiers.isDisjoint(with: blocked) else { break scan }
                segment.append(bind)
                blocked.formUnion(bind.names)
                deferred += pending
                pending = []
            case .plain(let item):
                guard !item.containsReturn else { break scan }
                pending.append(statements[next])
                blocked.formUnion(item.identifiers)
            case .returnBind:
                break scan
            }
            next += 1
        }
        let rest = ArraySlice(pending + statements[next...])

        var combined = segment.dropFirst().reduce("(\(segment[0].expression.trimmedDescription))") { combined, bind in
            "\(combined).liftA2(\(bind.expression.trimmedDescription)) { ($0, $1) }"
        }
        let method: String
        if rest.contains(where: \.isBind) {
            // A later bind depends on these, which needs a monad: check for one so the error says so
            combined = "Slingshot._doMonad(\(combined))"
            method = "flatMap"
        } else {
            method = "map"
        }

        if segment.count == 1, let name = segment[0].simpleName {
            lines.append("return \(combined).\(method) { \(name) in")
        } else {
            let bound = names.next()
            lines.append("return \(combined).\(method) { \(bound) in")
            for (index, bind) in segment.enumerated() {
                lines.append("\(bind.declaration) = \(bound)\(tuplePath(of: index, in: segment.count))")
            }
        }
        lines += deferred.map(\.source)
        lines.append(desugar(rest, names: &names))
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Where element `index` sits in the left-nested pairs liftA2 builds, e.g. `((a, b), c)`: `.0.0`, `.0.1`, `.1`
    private static func tuplePath(of index: Int, in count: Int) -> String {
        guard count > 1 else { return "" }
        let depth = index == 0 ? count - 1 : count - index
        return String(repeating: ".0", count: depth - 1) + (index == 0 ? ".0" : ".1")
    }

    private static func binderName(of closure: ClosureExprSyntax) -> String? {
        switch closure.signature?.parameterClause {
        case .simpleInput(let parameters) where parameters.count == 1:
            parameters.first?.name.text
        case .parameterClause(let clause) where clause.parameters.count == 1:
            clause.parameters.first.map { ($0.secondName ?? $0.firstName).text }
        default:
            nil
        }
    }
}

/// Replaces each `#do` nested in a block with its expansion.
private final class NestedDoExpander: SyntaxRewriter {
    let context: any MacroExpansionContext
    var errors: [any Error] = []

    init(context: any MacroExpansionContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        guard node.macroName.text == "do" else {
            return super.visit(node)
        }
        do {
            // The expansion handles the blocks nested in this one
            return try DoMacro.expansion(of: node, in: context).with(\.leadingTrivia, node.leadingTrivia)
        } catch {
            errors.append(error)
            return ExprSyntax(node)
        }
    }
}

/// Fresh names for closure parameters. Not `makeUniqueName`: its names start with `$`,
/// which Swift reads as a property wrapper projection when they're closure parameters.
private struct Names {
    private var count = 0

    mutating func next() -> String {
        count += 1
        return "__doBound\(count)"
    }
}

/// A `let`/`var` statement whose value is `bind(expression)`.
private struct Bind {
    let statement: VariableDeclSyntax
    let binding: PatternBindingSyntax
    let expression: ExprSyntax

    /// The statement without its value, e.g. `let user: User`
    var declaration: String {
        "\(statement.bindingSpecifier.text) \(binding.pattern.trimmedDescription)\(binding.typeAnnotation?.trimmedDescription ?? "")"
    }

    /// The bound name when the statement is just `let name = bind(...)`
    var simpleName: String? {
        guard statement.bindingSpecifier.tokenKind == .keyword(.let), binding.typeAnnotation == nil else { return nil }
        return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }

    var names: Set<String> {
        binding.pattern.identifiers
    }
}

private enum Statement {
    case bind(Bind)
    /// `return bind(expression)`
    case returnBind(ExprSyntax)
    case plain(CodeBlockItemSyntax)

    init(classifying item: CodeBlockItemSyntax, binder: String) throws {
        if let declaration = item.item.as(VariableDeclSyntax.self),
           declaration.bindings.count == 1,
           let binding = declaration.bindings.first,
           let value = binding.initializer?.value,
           let expression = bindArgument(of: value, binder: binder) {
            try rejectBinds(in: expression, binder: binder)
            self = .bind(Bind(statement: declaration, binding: binding, expression: expression))
        } else if let returnStatement = item.item.as(ReturnStmtSyntax.self),
                  let value = returnStatement.expression,
                  let expression = bindArgument(of: value, binder: binder) {
            try rejectBinds(in: expression, binder: binder)
            self = .returnBind(expression)
        } else {
            try rejectBinds(in: item, binder: binder)
            self = .plain(item)
        }
    }

    var isBind: Bool {
        if case .plain = self { false } else { true }
    }

    var source: String {
        switch self {
        case .bind(let bind): bind.statement.trimmedDescription
        case .returnBind(let expression): "return \(expression.trimmedDescription)"
        case .plain(let item): item.trimmedDescription
        }
    }
}

/// The `m` in `bind(m)`, when `expression` is exactly that call
private func bindArgument(of expression: ExprSyntax, binder: String) -> ExprSyntax? {
    guard let call = expression.as(FunctionCallExprSyntax.self),
          call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == binder,
          call.trailingClosure == nil,
          call.arguments.count == 1,
          let argument = call.arguments.first,
          argument.label == nil else {
        return nil
    }
    return argument.expression
}

/// Binds anywhere other than a top-level `let`/`var` or the final `return` can't be rewritten
private func rejectBinds(in node: some SyntaxProtocol, binder: String) throws {
    if let token = node.tokens(viewMode: .sourceAccurate).first(where: { $0.tokenKind == .identifier(binder) }) {
        throw error("\(binder) can only be used as a top-level `let x = \(binder)(m)`, or as `return \(binder)(m)`", at: token)
    }
}

private extension SyntaxProtocol {
    /// Every identifier in the node. Dependencies are judged by these names alone, ignoring shadowing,
    /// so they can only be over-reported: a false dependency costs concurrency, never correctness.
    var identifiers: Set<String> {
        Set(tokens(viewMode: .sourceAccurate).compactMap { token in
            if case .identifier(let name) = token.tokenKind { name } else { nil }
        })
    }

    /// Whether the node returns from the `#do` block, not counting returns inside closures and nested declarations
    var containsReturn: Bool {
        let finder = ReturnFinder(viewMode: .sourceAccurate)
        finder.walk(self)
        return finder.found
    }
}

private final class ReturnFinder: SyntaxVisitor {
    var found = false

    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        found = true
        return .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}

private struct DoMessage: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "Slingshot", id: "do") }
    var severity: DiagnosticSeverity { .error }
}

private func error(_ message: String, at node: some SyntaxProtocol) -> DiagnosticsError {
    DiagnosticsError(diagnostics: [Diagnostic(node: Syntax(node), message: DoMessage(message: message))])
}
