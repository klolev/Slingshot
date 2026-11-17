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
                DiagnosticSpec(message: "bind can only be used as a top-level `let x = bind(m)`, or as `return bind(m)`", line: 2, column: 12),
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
