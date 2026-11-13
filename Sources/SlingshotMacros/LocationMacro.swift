import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Makes an enum a location of a choreography.
///
///     @Location                                   enum Initiator {
///     enum Initiator {}                   →           static let name = "initiator"
///                                                     protocol Includes: LocationSet {}
///                                                     struct Reader: LocationReader { ... }
///                                                     static func member<S: Includes>(of: S.Type) -> Member<Initiator, S>
///                                                 }
///                                                 extension Initiator: Location {}
///
/// A set contains the location when it conforms to `Includes`, so the reader can read any value held by such a set
/// with a plain overload, and `member(of:)` only gives a proof for sets the compiler has checked.
/// The reader lives on the location rather than on a generic type because only code generated for one location
/// can say `S: Initiator.Includes`: Swift can't look a protocol up through a type parameter.
public struct LocationMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let location = try locationEnum(declaration, node)
        let name = location.name.text
        let access = accessModifier(of: location)
        let wireName = name.prefix(1).lowercased() + name.dropFirst()

        return [
            """
            /// How other nodes address \(raw: name).
            \(raw: access)static let name = "\(raw: wireName)"
            """,
            """
            /// The sets that contain \(raw: name): conforming a set to it puts \(raw: name) in the set.
            \(raw: access)protocol Includes: Slingshot.LocationSet {}
            """,
            """
            /// Reads the values \(raw: name) holds: its own, those of every set that includes it, and its facets of their faceted values.
            \(raw: access)struct Reader: Slingshot.LocationReader {
                \(raw: access)init(_unchecked: Void) {}

                \(raw: access)func callAsFunction<V>(_ v: Slingshot.At<\(raw: name), V>) -> V {
                    v.take()
                }

                \(raw: access)func callAsFunction<S: Includes, V>(_ v: Slingshot.At<S, V>) -> V {
                    v.take()
                }

                \(raw: access)func callAsFunction<S: Includes, V>(_ facets: Slingshot.Faceted<S, V>) -> V {
                    facets.take()
                }
            }
            """,
            """
            /// The proof that `S` contains \(raw: name), for code that's generic over its locations.
            \(raw: access)static func member<S: Includes>(of set: S.Type) -> Slingshot.Member<\(raw: name), S> {
                Slingshot.Member(_unchecked: ())
            }
            """,
            """
            /// The proof that `S` contains \(raw: name), as a set of one: for a conclave of just \(raw: name).
            \(raw: access)static func subset<S: Includes>(of set: S.Type) -> Slingshot.Subset<\(raw: name), S> {
                Slingshot.Subset(_unchecked: ())
            }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax,
                                 attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        // The member role reports a misplaced @Location; reporting it twice would only add noise
        guard declaration.is(EnumDeclSyntax.self), (declaration.as(EnumDeclSyntax.self)?.genericParameterClause == nil) else { return [] }
        // Already a Location, for example declared by hand: nothing to add
        guard !protocols.isEmpty else { return [] }
        return [DeclSyntax("extension \(type.trimmed): Slingshot.Location {}").cast(ExtensionDeclSyntax.self)]
    }

    private static func locationEnum(_ declaration: some DeclGroupSyntax, _ node: AttributeSyntax) throws -> EnumDeclSyntax {
        guard let location = declaration.as(EnumDeclSyntax.self) else {
            throw effectError("@Location goes on an enum: a location is a type, never a value", at: node)
        }
        if let generics = location.genericParameterClause {
            throw effectError("a location can't be generic: Swift doesn't allow the protocol it generates inside a generic type", at: generics)
        }
        return location
    }
}

/// Makes an enum the set of the locations whose `Includes` it conforms to.
///
///     @Locations                                          enum Peers: Initiator.Includes, Responder.Includes {
///     enum Peers: Initiator.Includes, Responder.Includes {}  →    static let members: [any Location.Type] = [Initiator.self, Responder.self]
///                                                         }
public struct LocationsMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let set = declaration.as(EnumDeclSyntax.self) else {
            throw effectError("@Locations goes on an enum that conforms to the Includes of each location in the set", at: node)
        }
        if let generics = set.genericParameterClause {
            throw effectError("a set of locations can't be generic", at: generics)
        }

        let members: [String] = (set.inheritanceClause?.inheritedTypes ?? []).compactMap { inherited in
            guard let member = inherited.type.as(MemberTypeSyntax.self), member.name.text == "Includes" else { return nil }
            return member.baseType.trimmedDescription
        }
        guard !members.isEmpty else {
            throw effectError("list the set's locations as conformances: @Locations enum Peers: Initiator.Includes, Responder.Includes {}", at: set.name)
        }
        var seen: Set<String> = []
        for member in members where !seen.insert(member).inserted {
            throw effectError("\(member) is listed twice", at: set.name)
        }

        let access = accessModifier(of: set)
        let name = set.name.text
        let containers = members.map { "\($0).Includes" }.joined(separator: " & ")
        return [
            """
            /// The locations in the set, for projection to send to each of them.
            \(raw: access)static let members: [any Slingshot.Location.Type] = [\(raw: members.map { "\($0).self" }.joined(separator: ", "))]
            """,
            """
            /// The proof that every location of \(raw: name) is in `S`, for a conclave of \(raw: name) inside a choreography among `S`.
            \(raw: access)static func subset<S: \(raw: containers)>(of set: S.Type) -> Slingshot.Subset<\(raw: name), S> {
                Slingshot.Subset(_unchecked: ())
            }
            """,
        ]
    }
}
