#if Macros
import SlingshotMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

// Only diagnostics: the successful expansions are covered by EffectsTest, which compiles and runs them
@Suite("effect macro diagnostics")
struct EffectsMacroExpansionTest {
    @Test("a family needs an Interpreter")
    func aFamilyNeedsAnInterpreter() {
        assertEffectsExpansion(
            """
            @EffectFamily
            enum Keychain {}
            """,
            expandedSource: """
            enum Keychain {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "declare the family's operations in a `protocol Interpreter` inside the enum", line: 2, column: 6),
            ]
        )
    }

    @Test("an Interpreter only declares methods")
    func anInterpreterOnlyDeclaresMethods() {
        assertEffectsExpansion(
            """
            @EffectFamily
            enum Keychain {
                protocol Interpreter {
                    var count: Int { get }
                }
            }
            """,
            expandedSource: """
            enum Keychain {
                protocol Interpreter {
                    var count: Int { get }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "an Interpreter can only declare methods: each one becomes an effect", line: 4, column: 9),
            ]
        )
    }
    
    @Test("a generic parameter has to appear in an argument")
    func aGenericParameterHasToAppearInAnArgument() {
        assertEffectsExpansion(
            """
            @EffectFamily
            enum Store {
                protocol Interpreter {
                    func make<V>() -> V
                }
            }
            """,
            expandedSource: """
            enum Store {
                protocol Interpreter {
                    func make<V>() -> V
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "`V` has to appear in an argument's type: an effect stores its arguments, and its type is inferred from them", line: 4, column: 19),
            ]
        )
    }

    @Test("a stack lists its families")
    func aStackListsItsFamilies() {
        assertEffectsExpansion(
            """
            @Effects
            enum App {}
            """,
            expandedSource: """
            enum App {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "list the stack's families as conformances: @Effects enum App: Keychain.Has, Log.Has {}", line: 2, column: 6),
            ]
        )
    }
}

func assertEffectsExpansion(_ source: String, expandedSource: String, diagnostics: [DiagnosticSpec] = [],
                            sourceLocation: Testing.SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expandedSource, diagnostics: diagnostics,
                         macroSpecs: ["EffectFamily": MacroSpec(type: EffectFamilyMacro.self),
                                      "Effects": MacroSpec(type: EffectsMacro.self)]) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}
#endif
