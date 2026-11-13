import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SlingshotMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [DoMacro.self, EffectFamilyMacro.self, EffectsMacro.self, LocationMacro.self, LocationsMacro.self]
}
