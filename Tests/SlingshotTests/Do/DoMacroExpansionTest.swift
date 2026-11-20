#if Macros
import SlingshotMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("#do expansion")
struct DoMacroExpansionTest {
    @Test("independent binds share a liftA2, dependent ones flatMap")
    func independentBindsShareALiftA2DependentOnesFlatMap() {
        assertDoExpansion(
            """
            #do { bind in
                let a = bind(x)
                let b = bind(y)
                let c = bind(f(a, b))
                return a + b + c
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((x).liftA2(y) {
                        Slingshot.Tuple($0, $1)
                    }).flatMap { __doBound1 in
                    return __doBound1.split { __doBound1_0, __doBound1_1 in
                        let a = __doBound1_0
                        let b = __doBound1_1
                        return (f(a, b)).map { c in
                            return a + b + c
                        }
                    }
                }
            }()
            """
        )
    }

    @Test("a value consumed after a later bind is carried past it")
    func aValueConsumedAfterALaterBindIsCarriedPastIt() {
        // start and exchange are independent, so they share a liftA2; follow depends on exchange, so it's a later
        // bind, and s is carried past it to finish
        assertDoExpansion(
            """
            #do { bind in
                let s = bind(start)
                let r = bind(exchange)
                let t = bind(follow(r))
                return bind(finish(consume s, t))
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((start).liftA2(exchange) {
                        Slingshot.Tuple($0, $1)
                    }).flatMap { __doBound1 in
                    return __doBound1.split { __doBound1_0, __doBound1_1 in
                        let s = __doBound1_0
                        let r = __doBound1_1
                        return Slingshot._doMonad((follow(r))).flatMap(carrying: s) { t, s in
                            return finish(consume s, t)
                        }
                    }
                }
            }()
            """
        )
    }

    @Test("a carried value goes through the split of independent binds")
    func aCarriedValueGoesThroughTheSplit() {
        assertDoExpansion(
            """
            #do { bind in
                let s = bind(start)
                let r = bind(follow(s))
                let a = bind(x)
                let b = bind(y(r))
                return bind(finish(consume s, a, b))
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((start)).flatMap { s in
                    return Slingshot._doMonad((follow(s)).liftA2(x) {
                            Slingshot.Tuple($0, $1)
                        }).flatMap(carrying: s) { __doBound1, s in
                        return __doBound1.split(carrying: s) { __doBound1_0, __doBound1_1, s in
                            let r = __doBound1_0
                            let a = __doBound1_1
                            return Slingshot._doMonad((y(r))).flatMap(carrying: s) { b, s in
                                return finish(consume s, a, b)
                            }
                        }
                    }
                }
            }()
            """
        )
    }

    @Test("plain statements between independent binds move after them")
    func plainStatementsBetweenIndependentBindsMoveAfterThem() {
        assertDoExpansion(
            """
            #do { bind in
                let a = bind(x)
                let k = 3
                let b = bind(y)
                return a + b + k
            }
            """,
            expandedSource: """
            {
                return (x).liftA2(y) {
                    Slingshot.Tuple($0, $1)
                } .map { __doBound1 in
                    return __doBound1.split { __doBound1_0, __doBound1_1 in
                        let a = __doBound1_0
                        let b = __doBound1_1
                        let k = 3
                        return a + b + k
                    }
                }
            }()
            """
        )
    }

    @Test("nested blocks are expanded in place")
    func nestedBlocksAreExpandedInPlace() {
        assertDoExpansion(
            """
            #do { bind in
                let a = bind(x)
                let b = bind(#do { bind in
                    let c = bind(y)
                    return c + a
                })
                return b
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((x)).flatMap { a in
                    return ({
                            return (y).map { c in
                                return c + a
                            }
                        }()).map { b in
                        return b
                    }
                }
            }()
            """
        )
    }

    @Test("an if with binds is rewritten branch by branch")
    func anIfWithBindsIsRewrittenBranchByBranch() {
        assertDoExpansion(
            """
            #do { bind in
                let n = bind(x)
                if n > 10 {
                    let m = bind(y(n))
                    return m + 1
                } else {
                    return n
                }
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((x)).flatMap { n in
                    if n > 10 {
                        return (y(n)).map { m in
                            return m + 1
                        }
                    } else {
                        return .pure(n)
                    }
                }
            }()
            """
        )
    }

    @Test("let x = if copies what follows into each branch")
    func letIfCopiesTheRestIntoEachBranch() {
        assertDoExpansion(
            """
            #do { bind in
                let n = bind(x)
                let b = if n > 1 { bind(y) } else { 0 }
                return n + b
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((x)).flatMap { n in
                    if n > 1 {
                        return (y).map { b in
                            return n + b
                        }
                    } else {
                        let b = 0
                        return .pure(n + b)
                    }
                }
            }()
            """
        )
    }

    @Test("an if with binds needs an else")
    func anIfWithBindsNeedsAnElse() {
        assertDoExpansion(
            """
            #do { bind in
                let n = bind(x)
                if n > 1 {
                    return bind(y)
                }
                return n
            }
            """,
            expandedSource: """
            #do { bind in
                let n = bind(x)
                if n > 1 {
                    return bind(y)
                }
                return n
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "an if with binds needs an else: every path has to end in a return", line: 3, column: 5),
            ]
        )
    }

    @Test("a bound condition is bound, then tested")
    func aBoundConditionIsBoundThenTested() {
        assertDoExpansion(
            """
            #do { bind in
                if bind(c) {
                    return 1
                } else {
                    return 2
                }
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((c)).flatMap { __doCond1 in
                    if __doCond1 {
                        return .pure(1)
                    } else {
                        return .pure(2)
                    }
                }
            }()
            """
        )
    }

    @Test("if let binds its value, then matches it with a switch that consumes a local copy")
    func ifLetMatchesWithASwitch() {
        assertDoExpansion(
            """
            #do { bind in
                if let s = bind(x) {
                    return s
                } else {
                    return 0
                }
            }
            """,
            expandedSource: """
            {
                return Slingshot._doMonad((x)).flatMap { __doCond1 in
                    let __doCond1Owned = __doCond1
                    switch consume __doCond1Owned {
                    case .some(let s):
                        return .pure(s)
                    case .none:
                        return .pure(0)
                    }
                }
            }()
            """
        )
    }

    @Test("return if returns from each branch")
    func returnIfReturnsFromEachBranch() {
        assertDoExpansion(
            """
            #do { bind in
                return if c {
                    bind(x)
                } else {
                    0
                }
            }
            """,
            expandedSource: """
            {
                if c {
                    return x
                } else {
                    return .pure(0)
                }
            }()
            """
        )
    }

    @Test("a bound condition can't have a type")
    func aBoundConditionCantHaveAType() {
        assertDoExpansion(
            """
            #do { bind in
                if let s: Int = bind(x) {
                    return s
                } else {
                    return 0
                }
            }
            """,
            expandedSource: """
            #do { bind in
                if let s: Int = bind(x) {
                    return s
                } else {
                    return 0
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "a bound condition can't have a type: give the program its type instead", line: 2, column: 13),
            ]
        )
    }

    @Test("a guard with binds needs something after it")
    func aGuardWithBindsNeedsSomethingAfterIt() {
        assertDoExpansion(
            """
            #do { bind in
                let n = bind(x)
                guard let m = bind(y) else { return 0 }
            }
            """,
            expandedSource: """
            #do { bind in
                let n = bind(x)
                guard let m = bind(y) else { return 0 }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "a guard with binds needs the rest of the block after it, ending in a return", line: 3, column: 5),
            ]
        )
    }

    @Test("returning a step without binding it warns")
    func returningAStepWithoutBindingItWarns() {
        assertDoExpansion(
            """
            #do { bind in
                let n = bind(x)
                return y.send(to: Bob.self)
            }
            """,
            expandedSource: """
            {
                return (x).map { n in
                    return y.send(to: Bob.self)
                }
            }()
            """,
            diagnostics: [
                DiagnosticSpec(message: "`send` makes a step, which this returns as a plain value: write `return bind(…)` to run it",
                               line: 3, column: 12, severity: .warning, fixIts: [FixItSpec(message: "Bind it with bind")]),
            ]
        )
    }

    @Test("returning pure warns, since the block wraps what it returns")
    func returningPureWarns() {
        assertDoExpansion(
            """
            #do { bind in
                let n = bind(x)
                return .pure(n)
            }
            """,
            expandedSource: """
            {
                return (x).map { n in
                    return .pure(n)
                }
            }()
            """,
            diagnostics: [
                DiagnosticSpec(message: "the block already wraps what it returns in `pure`: return the value itself",
                               line: 3, column: 12, severity: .warning, fixIts: [FixItSpec(message: "Return the value itself")]),
            ]
        )
    }

    @Test("a bind on its own drops its value")
    func aBindOnItsOwnDropsItsValue() {
        assertDoExpansion(
            """
            #do { bind in
                bind(x)
                return 1
            }
            """,
            expandedSource: """
            {
                return (x).map { __doBound1 in
                    let _ = __doBound1
                    return 1
                }
            }()
            """
        )
    }

    @Test("the binder has to be named")
    func theBinderHasToBeNamed() {
        assertDoExpansion(
            "#do { return 1 }",
            expandedSource: "#do { return 1 }",
            diagnostics: [
                DiagnosticSpec(message: "name the closure's parameter, then bind with it: #do { bind in let x = bind(m) ... }", line: 1, column: 5),
            ]
        )
    }

    @Test("binds inside expressions are rejected")
    func bindsInsideExpressionsAreRejected() {
        assertDoExpansion(
            """
            #do { bind in
                return bind(a) + 1
            }
            """,
            expandedSource: """
            #do { bind in
                return bind(a) + 1
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "bind can only be used as a top-level `let x = bind(m)`, as `return bind(m)`, as a whole condition of an if or guard, or in the branches of an if or switch that all return", line: 2, column: 12),
            ]
        )
    }

    @Test("a block can't end with a bind")
    func aBlockCantEndWithABind() {
        assertDoExpansion(
            """
            #do { bind in
                let x = bind(a)
            }
            """,
            expandedSource: """
            #do { bind in
                let x = bind(a)
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "#do must end with a return", line: 2, column: 5),
            ]
        )
    }
}

func assertDoExpansion(_ source: String, expandedSource: String, diagnostics: [DiagnosticSpec] = [],
                       sourceLocation: Testing.SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expandedSource, diagnostics: diagnostics,
                         macroSpecs: ["do": MacroSpec(type: DoMacro.self)]) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}
#endif
