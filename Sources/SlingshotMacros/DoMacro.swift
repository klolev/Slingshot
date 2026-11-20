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
        warnAboutUnboundSteps(in: closure.statements, marker: .call(binder), context: context)
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

    /// Warns about a `return` of what looks like a step without its bind: the block wraps what it returns as a value,
    /// so the step would never run, and the compiler's own error, about the expansion, doesn't say why.
    /// The macro can't see types, so this only knows Slingshot's own steps by name.
    static func warnAboutUnboundSteps(in statements: CodeBlockItemListSyntax, marker: BindMarker, context: some MacroExpansionContext) {
        let finder = UnboundStepFinder(marker: marker)
        finder.walk(statements)
        for (value, kind) in finder.found {
            switch kind {
            case .step(let name):
                let bound = marker.bind(value)
                context.diagnose(Diagnostic(
                    node: value,
                    message: DoWarning(message: "`\(name)` makes a step, which this returns as a plain value: write `return \(marker.example)` to run it"),
                    fixIt: FixIt(message: DoFixIt(message: "Bind it with \(marker.keyword)"),
                                 changes: [.replace(oldNode: Syntax(value), newNode: Syntax(ExprSyntax("\(raw: bound)")).with(\.leadingTrivia, value.leadingTrivia).with(\.trailingTrivia, value.trailingTrivia))])
                ))
            case .pure(let argument):
                context.diagnose(Diagnostic(
                    node: value,
                    message: DoWarning(message: "the block already wraps what it returns in `pure`: return the value itself"),
                    fixIt: FixIt(message: DoFixIt(message: "Return the value itself"),
                                 changes: [.replace(oldNode: Syntax(value), newNode: Syntax(argument).with(\.leadingTrivia, value.leadingTrivia).with(\.trailingTrivia, value.trailingTrivia))])
                ))
            }
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
        return .program(try desugar(statements[...], marker: marker, names: &names, owned: owned, declared: []))
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
    private static func desugar(_ statements: ArraySlice<Statement>, marker: BindMarker, names: inout Names,
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

        if case .branchBinding(let declaration, let binding, let branch) = statements[first] {
            // `let x = if … { A } else { B }; rest` is `if … { let x = A; rest } else { let x = B; rest }`:
            // each branch gets its own copy of the rest, so no join point has to capture what's in scope
            let joined = BranchJoin(kind: .binding(declaration, binding), rest: Array(statements[(first + 1)...]))
            lines.append(try emit(branch, joining: joined, marker: marker, names: &names, owned: owned, declared: declaredBefore))
            return lines.joined(separator: "\n")
        }

        if case .returnBranch(_, let branch) = statements[first] {
            // `return if … { A } else { B }` is `if … { return A } else { return B }`
            let emitted = try emit(branch, joining: BranchJoin(kind: .returning, rest: []), marker: marker, names: &names, owned: owned, declared: declaredBefore)
            if let after = statements[(first + 1)...].first {
                throw error("this can't run: it's after a return", at: after.node)
            }
            lines.append(emitted)
            return lines.joined(separator: "\n")
        }

        if case .guarding(let guarding) = statements[first] {
            // `guard conditions else { E }; rest` is `if conditions { rest } else { E }`, which binds its conditions
            let rest = statements[(first + 1)...]
            guard let last = rest.last, last.returns else {
                throw error("a guard with binds needs the rest of the block after it, ending in a return", at: guarding)
            }
            // checked as written, so errors point at the code: the rewrite is parsed anew
            var scratch = names
            _ = try conditionBinds(guarding.conditions, marker: marker)
            _ = try desugarBranch(guarding.body.statements, at: guarding.body, joining: nil, marker: marker, names: &scratch, owned: owned, declared: declaredBefore)
            _ = try desugar(rest, marker: marker, names: &scratch, owned: owned, declared: declaredBefore)

            let conditional = """
                if \(guarding.conditions.trimmedDescription) {
                \(rest.map(\.source).joined(separator: "\n"))
                } else {
                \(guarding.body.statements.trimmedDescription)
                }
                """
            lines.append(try desugar(parse(conditional, marker: marker)[...], marker: marker, names: &names, owned: owned, declared: declaredBefore))
            return lines.joined(separator: "\n")
        }

        if case .branch(let branch, _) = statements[first] {
            // rewritten first, so a missing else is reported as that, not as the code after it being unreachable
            let emitted = try emit(branch, marker: marker, names: &names, owned: owned, declared: declaredBefore)
            // Every path through it returns, so nothing after it could run
            if let after = statements[(first + 1)...].first {
                throw error("this can't run: every path through the if or switch before it returns", at: after.node)
            }
            lines.append(emitted)
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
            case .returnBind, .branch, .branchBinding, .returnBranch, .guarding:
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
        lines.append(try desugar(rest, marker: marker, names: &names, owned: owned, declared: declaredInside))
        lines += Array(repeating: "}", count: closings + 1)
        return lines.joined(separator: "\n")
    }

    /// An `if` or `switch` with binds, each branch rewritten as its own block. Branches are plain blocks, not closures,
    /// so they can consume the values in scope directly.
    private static func emit(_ branch: Branch, joining join: BranchJoin? = nil, marker: BindMarker, names: inout Names,
                             owned: Set<String>, declared: Set<String>) throws -> String {
        switch branch {
        case .conditional(let conditional):
            return try emit(conditional, joining: join, marker: marker, names: &names, owned: owned, declared: declared)
        case .switching(let switching):
            var lines = ["switch \(switching.subject.trimmedDescription) {"]
            for element in switching.cases {
                guard let switchCase = element.as(SwitchCaseSyntax.self) else {
                    throw error("#if can't go between the cases of a switch with binds", at: element)
                }
                lines.append(switchCase.label.trimmedDescription)
                lines.append(try desugarBranch(switchCase.statements, at: switchCase, joining: join, marker: marker, names: &names, owned: owned, declared: declared))
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }
    }

    private static func emit(_ conditional: IfExprSyntax, joining join: BranchJoin?, marker: BindMarker, names: inout Names,
                             owned: Set<String>, declared: Set<String>) throws -> String {
        guard let elseBody = conditional.elseBody else {
            let message = join == nil
                ? "an if with binds needs an else: every path has to end in a return"
                : "an if that gives a value needs an else"
            throw error(message, at: conditional.ifKeyword)
        }
        let binds = try conditionBinds(conditional.conditions, marker: marker)
        guard binds.contains(where: { $0 != nil }) else {
            return try emitBranches(conditional, elseBody: elseBody, joining: join, marker: marker, names: &names, owned: owned, declared: declared)
        }
        // checked as written, so errors point at the code: the rewrite below is parsed anew
        var scratch = names
        _ = try emitBranches(conditional, elseBody: elseBody, joining: join, marker: marker, names: &scratch, owned: owned, declared: declared)

        let then = conditional.body.statements.trimmedDescription
        let otherwise = switch elseBody {
        case .ifExpr(let nested): nested.trimmedDescription
        case .codeBlock(let block): block.statements.trimmedDescription
        }
        let (head, value) = chain(Array(zip(conditional.conditions, binds))[...], then: then, otherwise: otherwise, marker: marker, names: &names)
        var lines = head
        if let join {
            lines.append(join.statement(giving: value))
            lines += join.rest.map(\.source)
        } else {
            lines.append(value)
        }
        return try desugar(parse(lines.joined(separator: "\n"), marker: marker)[...], marker: marker, names: &names, owned: owned, declared: declared)
    }

    /// `if conditions { A } else { B }` with each branch rewritten
    private static func emitBranches(_ conditional: IfExprSyntax, elseBody: IfExprSyntax.ElseBody, joining join: BranchJoin?, marker: BindMarker,
                                     names: inout Names, owned: Set<String>, declared: Set<String>) throws -> String {
        let body = try desugarBranch(conditional.body.statements, at: conditional.body, joining: join, marker: marker, names: &names, owned: owned, declared: declared)
        var source = "if \(conditional.conditions.trimmedDescription) {\n\(body)\n}"
        switch elseBody {
        case .ifExpr(let nested):
            let emitted = try emit(nested, joining: join, marker: marker, names: &names, owned: owned, declared: declared)
            // with bound conditions it's statements that bind them, not an if
            let bound = try conditionBinds(nested.conditions, marker: marker).contains { $0 != nil }
            source += bound ? " else {\n\(emitted)\n}" : " else " + emitted
        case .codeBlock(let block):
            let otherwise = try desugarBranch(block.statements, at: block, joining: join, marker: marker, names: &names, owned: owned, declared: declared)
            source += " else {\n\(otherwise)\n}"
        }
        return source
    }

    /// An `if`'s conditions with binds among them, as statements that bind each one before testing it. The conditions
    /// before a bound one get an `if` of their own, so the bind only runs when they hold; the bound value is matched
    /// with a `switch` that consumes it, so it can be noncopyable. `otherwise` is copied to each place a condition can
    /// fail. Returns the statements before the final `if` or `switch`, and that `if` or `switch`.
    private static func chain(_ conditions: ArraySlice<(ConditionElementSyntax, ConditionBind?)>, then: String, otherwise: String,
                              marker: BindMarker, names: inout Names) -> (head: [String], value: String) {
        func text(_ conditions: ArraySlice<(ConditionElementSyntax, ConditionBind?)>) -> String {
            conditions.map { $0.0.condition.trimmedDescription }.joined(separator: ", ")
        }
        guard let index = conditions.firstIndex(where: { $0.1 != nil }), let bind = conditions[index].1 else {
            return ([], "if \(text(conditions)) {\n\(then)\n} else {\n\(otherwise)\n}")
        }
        // what runs once this condition holds: the conditions after it, then `then`
        func content(after index: Int, names: inout Names) -> String {
            let rest = conditions[(index + 1)...]
            guard !rest.isEmpty else { return then }
            let (head, value) = chain(rest, then: then, otherwise: otherwise, marker: marker, names: &names)
            return (head + [value]).joined(separator: "\n")
        }
        if index > conditions.startIndex {
            let inner = content(after: index - 1, names: &names)
            return ([], "if \(text(conditions[..<index])) {\n\(inner)\n} else {\n\(otherwise)\n}")
        }
        let name = names.condition()
        var head = ["let \(name) = \(marker.bind(bind.program))"]
        // the switch consumes a local: `consume` isn't supported on a closure's parameter when it's copyable, and
        // a noncopyable one is moved into the local, so either way the payload can be consumed
        let owned = "\(name)Owned"
        if case .truth = bind.match {} else {
            head.append("let \(owned) = \(name)")
        }
        let inner = content(after: index, names: &names)
        let value = switch bind.match {
        case .truth:
            "if \(name) {\n\(inner)\n} else {\n\(otherwise)\n}"
        case .some(let binding):
            "switch consume \(owned) {\ncase .some(\(binding)):\n\(inner)\ncase .none:\n\(otherwise)\n}"
        case .pattern(let pattern):
            "switch consume \(owned) {\ncase \(pattern):\n\(inner)\ndefault:\n\(otherwise)\n}"
        }
        return (head, value)
    }

    /// Each condition's bind, if it's a whole bind, rejecting binds anywhere else in the conditions
    private static func conditionBinds(_ conditions: ConditionElementListSyntax, marker: BindMarker) throws -> [ConditionBind?] {
        try conditions.map { element in
            if let bind = try ConditionBind(element, marker: marker) {
                try marker.rejectBinds(in: bind.program)
                return bind
            }
            try marker.rejectBinds(in: element)
            return nil
        }
    }

    /// Statements the macro wrote, classified like the block's own
    private static func parse(_ source: String, marker: BindMarker) throws -> [Statement] {
        let statements: CodeBlockItemListSyntax = "\(raw: source)"
        return try statements.map { try Statement(classifying: $0, marker: marker) }
    }

    /// One branch's statements as a block that returns a program: binds are rewritten, and a branch without any
    /// returns its value in `pure`
    private static func desugarBranch(_ statements: CodeBlockItemListSyntax, at node: some SyntaxProtocol, joining join: BranchJoin?,
                                      marker: BindMarker, names: inout Names, owned: Set<String>, declared: Set<String>) throws -> String {
        var classified: [Statement]
        if let join {
            // the branch's last line is its value: bind it as the declared name, then run the rest
            guard let last = statements.last,
                  let value = last.item.as(ExpressionStmtSyntax.self)?.expression ?? last.item.as(ExprSyntax.self) else {
                throw error("the last line of each branch of \(join.form) has to be its value", at: statements.last.map { Syntax($0) } ?? Syntax(node))
            }
            let head = try statements.dropLast().map { try Statement(classifying: $0, marker: marker) }
            classified = head + (try parse(join.statement(giving: value.trimmedDescription), marker: marker)) + join.rest
        } else {
            classified = try statements.map { try Statement(classifying: $0, marker: marker) }
        }
        guard let last = classified.last, last.returns else {
            throw error("each branch of an if or switch with binds has to end in a return", at: classified.last?.node ?? Syntax(node))
        }
        // an if or switch whose every path returns, with no binds: rewritten too, so its returns are wrapped in pure
        if case .plain(let item) = last {
            if let returned = item.item.as(ReturnStmtSyntax.self) {
                // `.pure(if …)` isn't Swift: if and switch expressions can't be arguments
                if let branch = Branch(returned.expression) {
                    classified[classified.count - 1] = .returnBranch(returned, branch)
                }
            } else if let branch = Branch(item) {
                classified[classified.count - 1] = .branch(branch, item)
            }
        }
        if classified.contains(where: \.isBind) {
            return try desugar(classified[...], marker: marker, names: &names, owned: owned, declared: declared)
        }
        // no binds: the value it returns is wrapped in pure, like a block without binds
        if case .plain(let item) = last, let returned = item.item.as(ReturnStmtSyntax.self),
           !classified.dropLast().contains(where: { $0.node.containsReturn }) {
            let value = returned.expression?.trimmedDescription ?? "()"
            return (classified.dropLast().map(\.source) + ["return .pure(\(value))"]).joined(separator: "\n")
        }
        return "return .pure({\n\(classified.map(\.source).joined(separator: "\n"))\n}())"
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
    private var conditions = 0
    static let conditionPrefix = "__doCond"

    /// A name for a bound condition's value
    mutating func condition() -> String {
        conditions += 1
        return "\(Self.conditionPrefix)\(conditions)"
    }

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

/// What follows `let x = if …`: each branch binds its value as `x`, then runs a copy of the rest.
/// Or `return if …`: each branch returns its value.
private struct BranchJoin {
    enum Kind {
        case binding(VariableDeclSyntax, PatternBindingSyntax)
        case returning
    }

    let kind: Kind
    let rest: [Statement]

    /// The statement that gives a branch's value to what follows
    func statement(giving value: String) -> String {
        switch kind {
        case .binding(let declaration, let binding):
            "\(declaration.bindingSpecifier.text) \(binding.pattern.trimmedDescription)\(binding.typeAnnotation?.trimmedDescription ?? "") = \(value)"
        case .returning:
            "return \(value)"
        }
    }

    /// How the code it came from reads, for errors
    var form: String {
        switch kind {
        case .binding(let declaration, let binding):
            "`\(declaration.bindingSpecifier.text) \(binding.pattern.trimmedDescription) = if …` or `= switch …`"
        case .returning:
            "`return if …` or `return switch …`"
        }
    }
}

/// An `if` or `switch` statement with binds in its branches
private enum Branch {
    case conditional(IfExprSyntax)
    case switching(SwitchExprSyntax)

    init?(_ item: CodeBlockItemSyntax) {
        guard let expression = item.item.as(ExpressionStmtSyntax.self)?.expression ?? item.item.as(ExprSyntax.self) else {
            return nil
        }
        self.init(expression)
    }

    init?(_ expression: ExprSyntax?) {
        if let conditional = expression?.as(IfExprSyntax.self) {
            self = .conditional(conditional)
        } else if let switching = expression?.as(SwitchExprSyntax.self) {
            self = .switching(switching)
        } else {
            return nil
        }
    }

    /// Whether the macro wrote it to test a bound condition's value: it's rewritten even when nothing in it binds,
    /// since it's where the bind's continuation returns
    var isSynthesized: Bool {
        let subject: ExprSyntax
        switch self {
        case .conditional(let conditional):
            guard conditional.conditions.count == 1, case .expression(let condition)? = conditional.conditions.first?.condition else {
                return false
            }
            subject = condition
        case .switching(let switching):
            subject = switching.subject.as(ConsumeExprSyntax.self)?.expression ?? switching.subject
        }
        return subject.as(DeclReferenceExprSyntax.self)?.baseName.text.hasPrefix(Names.conditionPrefix) == true
    }
}

/// A condition of an `if` or `guard` that's a whole bind: `let x = await m`, `case p = await m`, or `await m`
private struct ConditionBind {
    enum Match {
        /// `let x`, matched against `.some`
        case some(String)
        /// `case p`
        case pattern(String)
        /// a Bool
        case truth
    }

    let program: ExprSyntax
    let match: Match

    init?(_ element: ConditionElementSyntax, marker: BindMarker) throws {
        switch element.condition {
        case .expression(let expression):
            guard let program = marker.argument(of: expression) else { return nil }
            self.program = program
            match = .truth
        case .optionalBinding(let binding):
            guard let value = binding.initializer?.value, let program = marker.argument(of: value) else { return nil }
            if let typeAnnotation = binding.typeAnnotation {
                throw error("a bound condition can't have a type: give the program its type instead", at: typeAnnotation)
            }
            self.program = program
            match = .some("\(binding.bindingSpecifier.text) \(binding.pattern.trimmedDescription)")
        case .matchingPattern(let matching):
            guard let program = marker.argument(of: matching.initializer.value) else { return nil }
            if let typeAnnotation = matching.typeAnnotation {
                throw error("a bound condition can't have a type: give the program its type instead", at: typeAnnotation)
            }
            self.program = program
            match = .pattern(matching.pattern.trimmedDescription)
        default:
            return nil
        }
    }
}

private enum Statement {
    case bind(Bind)
    /// `return bind(expression)`
    case returnBind(ExprSyntax)
    /// An `if` or `switch` with binds in its branches, each ending in a return
    case branch(Branch, CodeBlockItemSyntax)
    /// `let x = if …` or `let x = switch …` with binds in its branches, each ending in its value
    case branchBinding(VariableDeclSyntax, PatternBindingSyntax, Branch)
    /// `return if …` or `return switch …` with binds in its branches or conditions, each branch ending in its value
    case returnBranch(ReturnStmtSyntax, Branch)
    /// A `guard` that binds in its conditions or its else: it becomes an `if` holding the rest of the block
    case guarding(GuardStmtSyntax)
    case plain(CodeBlockItemSyntax)

    init(classifying item: CodeBlockItemSyntax, marker: BindMarker) throws {
        if let declaration = item.item.as(VariableDeclSyntax.self),
           declaration.bindings.count == 1,
           let binding = declaration.bindings.first,
           let value = binding.initializer?.value,
           let expression = marker.argument(of: value) {
            try marker.rejectBinds(in: expression)
            self = .bind(Bind(statement: declaration, binding: binding, expression: expression))
        } else if let declaration = item.item.as(VariableDeclSyntax.self),
                  declaration.bindings.count == 1,
                  let binding = declaration.bindings.first,
                  let value = binding.initializer?.value,
                  let branch = Branch(value),
                  marker.isUsed(in: value) || branch.isSynthesized {
            // its branches are classified when they're rewritten
            self = .branchBinding(declaration, binding, branch)
        } else if let returnStatement = item.item.as(ReturnStmtSyntax.self),
                  let value = returnStatement.expression,
                  let expression = marker.argument(of: value) {
            try marker.rejectBinds(in: expression)
            self = .returnBind(expression)
        } else if let returnStatement = item.item.as(ReturnStmtSyntax.self),
                  let branch = Branch(returnStatement.expression),
                  marker.isUsed(in: returnStatement) || branch.isSynthesized {
            // its branches are classified when they're rewritten
            self = .returnBranch(returnStatement, branch)
        } else if let branch = Branch(item), marker.isUsed(in: item) || branch.isSynthesized {
            // its branches are classified when they're rewritten
            self = .branch(branch, item)
        } else if let guarding = item.item.as(GuardStmtSyntax.self), marker.isUsed(in: guarding) {
            self = .guarding(guarding)
        } else {
            try marker.rejectBinds(in: item)
            self = .plain(item)
        }
    }

    /// The statement, for errors
    var node: Syntax {
        switch self {
        case .bind(let bind): Syntax(bind.statement)
        case .returnBind(let expression): Syntax(expression)
        case .branch(_, let item): Syntax(item)
        case .branchBinding(let declaration, _, _): Syntax(declaration)
        case .returnBranch(let returnStatement, _): Syntax(returnStatement)
        case .guarding(let guarding): Syntax(guarding)
        case .plain(let item): Syntax(item)
        }
    }

    /// Whether the statement ends its block: a return, or a branch whose every path returns
    var returns: Bool {
        switch self {
        case .returnBind, .branch, .returnBranch: true
        case .bind, .branchBinding, .guarding: false
        case .plain(let item): allPathsReturn(item)
        }
    }

    var isBind: Bool {
        if case .plain = self { false } else { true }
    }

    var source: String {
        switch self {
        case .bind(let bind): bind.statement.trimmedDescription
        case .returnBind(let expression): "return \(expression.trimmedDescription)"
        case .branch(_, let item): item.trimmedDescription
        case .branchBinding(let declaration, _, _): declaration.trimmedDescription
        case .returnBranch(let returnStatement, _): returnStatement.trimmedDescription
        case .guarding(let guarding): guarding.trimmedDescription
        case .plain(let item): item.trimmedDescription
        }
    }

    /// The names the statement declares at the top level of the block
    var declaredNames: Set<String> {
        switch self {
        case .bind(let bind):
            bind.names
        case .returnBind, .branch, .returnBranch, .guarding:
            // a branch's declarations stay inside its branches, and a guard's go with the rest of the block
            []
        case .branchBinding(_, let binding, _):
            binding.pattern.identifiers
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
        case .branch(_, let item): item.consumedNames
        case .branchBinding(let declaration, _, _): declaration.consumedNames
        case .returnBranch(let returnStatement, _): returnStatement.consumedNames
        case .guarding(let guarding): guarding.consumedNames
        case .plain(let item): item.consumedNames
        }
    }
}

/// Whether every path through the statement returns: a return, or an if with an else or a switch whose branches all do
private func allPathsReturn(_ item: CodeBlockItemSyntax) -> Bool {
    if item.item.is(ReturnStmtSyntax.self) {
        return true
    }
    switch Branch(item) {
    case .conditional(let conditional):
        return allPathsReturn(conditional)
    case .switching(let switching):
        return switching.cases.allSatisfy { element in
            element.as(SwitchCaseSyntax.self)?.statements.last.map { allPathsReturn($0) } ?? false
        }
    case nil:
        return false
    }
}

private func allPathsReturn(_ conditional: IfExprSyntax) -> Bool {
    guard let last = conditional.body.statements.last, allPathsReturn(last) else { return false }
    switch conditional.elseBody {
    case .ifExpr(let nested): return allPathsReturn(nested)
    case .codeBlock(let block): return block.statements.last.map { allPathsReturn($0) } ?? false
    case nil: return false
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

    /// A bind as the block writes it, for messages: `bind(…)` or `await …`
    var example: String {
        switch self {
        case .call(let binder): "\(binder)(…)"
        case .await: "await …"
        }
    }

    /// What binds, for messages: `bind` or `await`
    var keyword: String {
        switch self {
        case .call(let binder): binder
        case .await: "await"
        }
    }

    /// `m` as a bind, written the way the block writes its binds
    func bind(_ program: ExprSyntax) -> String {
        switch self {
        case .call(let binder): "\(binder)(\(program.trimmedDescription))"
        case .await: "await \(program.trimmedDescription)"
        }
    }

    /// Whether the node binds anywhere outside closures: for an `if` or `switch`, whether its branches need rewriting
    func isUsed(in node: some SyntaxProtocol) -> Bool {
        switch self {
        case .call(let binder):
            return node.tokens(viewMode: .sourceAccurate).contains { $0.tokenKind == .identifier(binder) }
        case .await:
            let finder = AwaitFinder(viewMode: .sourceAccurate)
            finder.walk(node)
            return finder.found != nil
        }
    }

    /// Binds anywhere other than a top-level `let`/`var` or the final `return` can't be rewritten
    func rejectBinds(in node: some SyntaxProtocol) throws {
        switch self {
        case .call(let binder):
            if let token = node.tokens(viewMode: .sourceAccurate).first(where: { $0.tokenKind == .identifier(binder) }) {
                throw error("\(binder) can only be used as a top-level `let x = \(binder)(m)`, as `return \(binder)(m)`, as a whole condition of an if or guard, or in the branches of an if or switch that all return", at: token)
            }
        case .await:
            // awaits inside closures belong to them, like an async Embedding.run body
            let finder = AwaitFinder(viewMode: .sourceAccurate)
            finder.walk(node)
            if let found = finder.found {
                throw error("in @Do, await can only be used as a top-level `let x = await m`, as `return await m`, as a whole condition of an if or guard, or in the branches of an if or switch that all return", at: found)
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
        DoMacro.warnAboutUnboundSteps(in: body.statements, marker: .await, context: context)
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

/// The values a block returns that look like Slingshot steps or `.pure(…)`, outside closures and nested functions:
/// a plain `return`'s value, and each branch's value in `return if …` and `return switch …`
private final class UnboundStepFinder: SyntaxVisitor {
    enum Kind {
        case step(String)
        case pure(ExprSyntax)
    }

    /// Slingshot's steps, by the name of the call that makes them
    static let steps: Set<String> = [
        "locally", "parallel", "congruently", "constant", "send", "fanIn", "naked", "reading", "using", "conclave", "branch",
    ]

    let marker: BindMarker
    var found: [(ExprSyntax, Kind)] = []

    init(marker: BindMarker) {
        self.marker = marker
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        if let value = node.expression {
            check(value)
        }
        return .visitChildren
    }

    private func check(_ value: ExprSyntax) {
        if marker.argument(of: value) != nil {
            return
        }
        switch Branch(value) {
        case .conditional(let conditional):
            check(conditional)
        case .switching(let switching):
            for element in switching.cases {
                if let last = element.as(SwitchCaseSyntax.self)?.statements.last, let expression = Self.expression(of: last) {
                    check(expression)
                }
            }
        case nil:
            if let kind = Self.kind(of: value) {
                found.append((value, kind))
            }
        }
    }

    private func check(_ conditional: IfExprSyntax) {
        if let last = conditional.body.statements.last, let expression = Self.expression(of: last) {
            check(expression)
        }
        switch conditional.elseBody {
        case .ifExpr(let nested):
            check(nested)
        case .codeBlock(let block):
            if let last = block.statements.last, let expression = Self.expression(of: last) {
                check(expression)
            }
        case nil:
            break
        }
    }

    private static func expression(of item: CodeBlockItemSyntax) -> ExprSyntax? {
        item.item.as(ExpressionStmtSyntax.self)?.expression ?? item.item.as(ExprSyntax.self)
    }

    private static func kind(of value: ExprSyntax) -> Kind? {
        guard let call = value.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        let name = member.declName.baseName.text
        if name == "pure", call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil {
            return .pure(argument.expression)
        }
        if steps.contains(name) {
            return .step(name)
        }
        // Embedding.run makes a step; other `run`s, like a program's, are async calls
        if name == "run", member.base?.trimmedDescription.hasSuffix("Embedding") == true {
            return .step("Embedding.run")
        }
        return nil
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

private struct DoWarning: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "Slingshot", id: "do.unbound") }
    var severity: DiagnosticSeverity { .warning }
}

private struct DoFixIt: FixItMessage {
    let message: String
    var fixItID: MessageID { MessageID(domain: "Slingshot", id: "do.bind") }
}

private struct DoMessage: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "Slingshot", id: "do") }
    var severity: DiagnosticSeverity { .error }
}

private func error(_ message: String, at node: some SyntaxProtocol) -> DiagnosticsError {
    DiagnosticsError(diagnostics: [Diagnostic(node: Syntax(node), message: DoMessage(message: message))])
}
