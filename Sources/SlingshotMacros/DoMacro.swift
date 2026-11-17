import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Rewrites a `#do` block into `map`, `flatMap` and `liftA2`, the way Haskell desugars `do` with ApplicativeDo.
///
///     #do { bind in                         { return (fetchUser(id)).liftA2(fetchConfig()) { Slingshot.Tuple($0, $1) }.map { bound in
///         let user = bind(fetchUser(id))         return bound.split { bound_0, bound_1 in
///         let config = bind(fetchConfig())  →        let user = bound_0
///         return render(user, config)                let config = bound_1
///     }                                              return render(user, config)
///                                             } } }()
///
/// The values are combined in Slingshot's `Tuple`, not a Swift tuple: a noncopyable value can't go in a Swift tuple,
/// and `#do` can't tell which values are noncopyable.
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
        let body = try expandNested(closure.statements, in: context, at: closure)
        switch try desugarBlock(body, marker: .call(binder), name: "#do") {
        case .pure(let value):
            return "\(raw: ".pure(\(value))")"
        case .program(let desugared):
            return "\(raw: "{\n\(desugared)\n}()")"
        }
    }

    /// A rewritten block: with no binds, just its value
    enum Desugared {
        /// The block's code as an expression, to wrap in `pure`
        case pure(String)
        /// Statements ending in a return
        case program(String)
    }

    /// The statements of a `#do` block or an `@Do` body, rewritten into `flatMap`, `map` and `liftA2`
    static func desugarBlock(_ body: CodeBlockItemListSyntax, marker: BindMarker, name: String) throws -> Desugared {
        let statements = try body.map { try Statement(classifying: $0, marker: marker) }

        guard statements.contains(where: \.isBind) else {
            return .pure("{\n\(body.trimmedDescription)\n}()")
        }
        if let last = statements.last, case .bind(let bind) = last {
            throw error("\(name) must end with a return", at: bind.statement)
        }
        var names = Names()
        // Noncopyable values the block consumes with `consume name`: carried through the program to that point
        let owned = body.consumedNames
        return .program(try desugar(statements[...], names: &names, owned: owned, declared: []))
    }

    /// Replaces each `#do` nested in a block with its expansion
    static func expandNested(_ statements: CodeBlockItemListSyntax, in context: some MacroExpansionContext, at node: some SyntaxProtocol) throws -> CodeBlockItemListSyntax {
        let expander = NestedDoExpander(context: context)
        let body = expander.rewrite(statements)
        if let error = expander.errors.first {
            throw error
        }
        guard let body = body.as(CodeBlockItemListSyntax.self) else {
            throw error("couldn't expand the #do blocks nested in this one", at: node)
        }
        return body
    }

    /// Emits `statements` as a closure body: plain statements as written, binds as calls whose closures hold the rest.
    /// `owned` are the names the block consumes with `consume`, and `declared` the names already in scope.
    private static func desugar(_ statements: ArraySlice<Statement>, names: inout Names,
                                owned: Set<String>, declared: Set<String>) throws -> String {
        guard let first = statements.firstIndex(where: \.isBind) else {
            return statements.map(\.source).joined(separator: "\n")
        }
        var lines = statements[..<first].map(\.source)
        let declaredBefore = declared.union(statements[..<first].flatMap(\.declaredNames))

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

        // Owned values declared before these binds and consumed after them: the continuation is a closure, which
        // could only borrow them, so the program carries them and hands them back as the continuation's parameters
        let boundHere = Set(segment.flatMap(\.names))
        let consumedLater = Set((deferred + rest).flatMap(\.consumedNames))
        let carried = owned.intersection(declaredBefore).intersection(consumedLater).subtracting(boundHere).sorted()
        guard carried.count <= 3 else {
            throw error("\(carried.joined(separator: ", ")) are all consumed after this bind: #do can carry at most 3 values past one, so consume some sooner", at: segment[0].statement)
        }

        var combined = segment.dropFirst().reduce("(\(segment[0].expression.trimmedDescription))") { combined, bind in
            "\(combined).liftA2(\(bind.expression.trimmedDescription)) { Slingshot.Tuple($0, $1) }"
        }
        let method: String
        if rest.contains(where: \.isBind) {
            // A later bind depends on these, which needs a monad: check for one so the error says so
            combined = "Slingshot._doMonad(\(combined))"
            method = "flatMap"
        } else {
            method = "map"
        }

        let carrying = carried.isEmpty ? "" : "(carrying: \(carried.joined(separator: ", ")))"
        // the split closures opened for liftA2's pairs, closed after the rest
        var closings = 0
        let carriedParameters = carried.map { ", \($0)" }.joined()
        if segment.count == 1, let name = segment[0].simpleName {
            lines.append("return \(combined).\(method)\(carrying) { \(name)\(carriedParameters) in")
        } else {
            let bound = names.next()
            lines.append("return \(combined).\(method)\(carrying) { \(bound)\(carriedParameters) in")
            // liftA2 nests pairs to the left, ((a, b), c): split them from the outside in, each value a parameter
            let count = segment.count
            // a single bind with a pattern or a type annotation has no pair to split: its value is the parameter
            func element(_ index: Int) -> String { count == 1 ? bound : "\(bound)_\(index)" }
            func left(_ level: Int) -> String {
                level == count - 1 ? bound : level == 0 ? element(0) : "\(bound)_left\(level)"
            }
            // carried values are parameters of the continuation: split's closure would only capture them,
            // so they go through each split as parameters too
            let splitCall = carried.isEmpty ? "split" : "split(carrying: \(carried.joined(separator: ", ")))"
            for level in stride(from: count - 1, through: 1, by: -1) {
                lines.append("return \(left(level)).\(splitCall) { \(left(level - 1)), \(element(level))\(carriedParameters) in")
            }
            for (index, bind) in segment.enumerated() {
                lines.append("\(bind.declaration) = \(element(index))")
            }
            closings += count - 1
        }
        lines += deferred.map(\.source)
        let declaredInside = declaredBefore.union(boundHere).union(deferred.flatMap(\.declaredNames))
        lines.append(try desugar(rest, names: &names, owned: owned, declared: declaredInside))
        lines += Array(repeating: "}", count: closings + 1)
        return lines.joined(separator: "\n")
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

    init(classifying item: CodeBlockItemSyntax, marker: BindMarker) throws {
        if let declaration = item.item.as(VariableDeclSyntax.self),
           declaration.bindings.count == 1,
           let binding = declaration.bindings.first,
           let value = binding.initializer?.value,
           let expression = marker.argument(of: value) {
            try marker.rejectBinds(in: expression)
            self = .bind(Bind(statement: declaration, binding: binding, expression: expression))
        } else if let returnStatement = item.item.as(ReturnStmtSyntax.self),
                  let value = returnStatement.expression,
                  let expression = marker.argument(of: value) {
            try marker.rejectBinds(in: expression)
            self = .returnBind(expression)
        } else {
            try marker.rejectBinds(in: item)
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

    /// The names the statement declares at the top level of the block
    var declaredNames: Set<String> {
        switch self {
        case .bind(let bind):
            bind.names
        case .returnBind:
            []
        case .plain(let item):
            item.item.as(VariableDeclSyntax.self).map { declaration in
                Set(declaration.bindings.flatMap { $0.pattern.identifiers })
            } ?? []
        }
    }

    /// The names the statement consumes with `consume name`
    var consumedNames: Set<String> {
        switch self {
        case .bind(let bind): bind.statement.consumedNames
        case .returnBind(let expression): expression.consumedNames
        case .plain(let item): item.consumedNames
        }
    }
}

/// How a block marks its binds: `#do` with a call to its closure's parameter, `@Do` with `await`
enum BindMarker {
    /// `bind(m)`, named after the `#do` closure's parameter
    case call(String)
    /// `await m`, in an `@Do` function's body
    case await

    /// The `m` in `bind(m)` or `await m`, when `expression` is exactly that
    func argument(of expression: ExprSyntax) -> ExprSyntax? {
        switch self {
        case .call(let binder):
            guard let call = expression.as(FunctionCallExprSyntax.self),
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == binder,
                  call.trailingClosure == nil,
                  call.arguments.count == 1,
                  let argument = call.arguments.first,
                  argument.label == nil else {
                return nil
            }
            return argument.expression
        case .await:
            return expression.as(AwaitExprSyntax.self)?.expression
        }
    }

    /// Binds anywhere other than a top-level `let`/`var` or the final `return` can't be rewritten
    func rejectBinds(in node: some SyntaxProtocol) throws {
        switch self {
        case .call(let binder):
            if let token = node.tokens(viewMode: .sourceAccurate).first(where: { $0.tokenKind == .identifier(binder) }) {
                throw error("\(binder) can only be used as a top-level `let x = \(binder)(m)`, or as `return \(binder)(m)`", at: token)
            }
        case .await:
            // awaits inside closures belong to them, like an async Embedding.run body
            let finder = AwaitFinder(viewMode: .sourceAccurate)
            finder.walk(node)
            if let found = finder.found {
                throw error("in @Do, await can only be used as a top-level `let x = await m`, or as `return await m`", at: found)
            }
        }
    }
}

/// The first `await` outside closures and nested declarations
private final class AwaitFinder: SyntaxVisitor {
    var found: AwaitExprSyntax?

    override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        if found == nil {
            found = node
        }
        return .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

/// Rewrites a function's body the way `#do` rewrites its block, with `await` marking each bind: the function's
/// return type tells every step its type, so there's no binder. The body isn't type-checked as written, only after.
///
///     @Do                                             return (fetchUser(id)).liftA2(fetchConfig()) { … }.map { …
///     func page(_ id: ID) -> Freer<App, Page> {           let user = …
///         let user = await fetchUser(id)          →      let config = …
///         let config = await fetchConfig()               return render(user, config)
///         return render(user, config)                 }
///     }
public struct DoBodyMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let body = declaration.body else {
            throw error("@Do rewrites a function's body: give the function one", at: node)
        }
        let statements = try DoMacro.expandNested(body.statements, in: context, at: body)
        let source = switch try DoMacro.desugarBlock(statements, marker: .await, name: "@Do") {
        case .pure(let value): "return .pure(\(value))"
        case .program(let desugared): desugared
        }
        let file: SourceFileSyntax = "\(raw: source)"
        return Array(file.statements)
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

    /// The names consumed with `consume name` anywhere in the node
    var consumedNames: Set<String> {
        let finder = ConsumeFinder(viewMode: .sourceAccurate)
        finder.walk(self)
        return finder.names
    }

    /// Whether the node returns from the `#do` block, not counting returns inside closures and nested declarations
    var containsReturn: Bool {
        let finder = ReturnFinder(viewMode: .sourceAccurate)
        finder.walk(self)
        return finder.found
    }
}

private final class ConsumeFinder: SyntaxVisitor {
    var names: Set<String> = []

    override func visit(_ node: ConsumeExprSyntax) -> SyntaxVisitorContinueKind {
        if let reference = node.expression.as(DeclReferenceExprSyntax.self) {
            names.insert(reference.baseName.text)
        }
        return .visitChildren
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
