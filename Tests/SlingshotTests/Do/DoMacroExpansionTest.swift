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
                        ($0, $1)
                    }).flatMap { __doBound1 in
                    let a = __doBound1.0
                    let b = __doBound1.1
                    return (f(a, b)).map { c in
                        return a + b + c
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
                    ($0, $1)
                } .map { __doBound1 in
                    let a = __doBound1.0
                    let b = __doBound1.1
                    let k = 3
                    return a + b + k
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
