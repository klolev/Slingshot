#if Macros
import SlingshotMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

// Only diagnostics: the successful expansions are covered by ChoreographyTest, which compiles and runs them
@Suite("location macro diagnostics")
struct LocationMacroExpansionTest {
    @Test("a location is an enum")
    func aLocationIsAnEnum() {
        assertLocationExpansion(
            """
            @Location
            struct Server {}
            """,
            expandedSource: """
            struct Server {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Location goes on an enum: a location is a type, never a value", line: 1, column: 1),
            ]
        )
    }

    @Test("a set lists its locations")
    func aSetListsItsLocations() {
        assertLocationExpansion(
            """
            @Locations
            enum Peers {}
            """,
            expandedSource: """
            enum Peers {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "list the set's locations as conformances: @Locations enum Peers: Initiator.Includes, Responder.Includes {}", line: 2, column: 6),
            ]
        )
    }
}

func assertLocationExpansion(_ source: String, expandedSource: String, diagnostics: [DiagnosticSpec] = [],
                             sourceLocation: Testing.SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expandedSource, diagnostics: diagnostics,
                         macroSpecs: ["Location": MacroSpec(type: LocationMacro.self, conformances: ["Location"]),
                                      "Locations": MacroSpec(type: LocationsMacro.self)]) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}
#endif
