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
///                                                     static func locally<S: Includes, …>(borrowing facets: Faceted<S, …>, …)
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
        let declaresLocal = declaresTypealias("Local", in: location)

        let local: [DeclSyntax] = declaresLocal ? [] : [
            """
            /// \(raw: name)'s local code is plain async code: declare `typealias Local = SomeStack` for other effects.
            \(raw: access)typealias Local = Slingshot.Embedding.Family
            """,
        ]
        // Swift only checks Local against `EffectStack` once something uses the location: this checks it here
        let check: [DeclSyntax] = !declaresLocal ? [] : [
            """
            /// Fails to compile unless `Local` is an effect stack: write `SomeFamily.Family` for a family on its own.
            private typealias LocalIsAnEffectStack = Slingshot.EffectStackCheck<Local>
            """,
        ]
        return local + check + [
            """
            /// As a set of one, \(raw: name) shares all of its local effects with itself.
            \(raw: access)typealias Shared = Local
            """,
            """
            /// \(raw: name)'s shared program is its own local program: the only member is \(raw: name) itself.
            \(raw: access)static func lift<L: Slingshot.Location, V: ~Copyable>(_ program: consuming Slingshot.Freer<Shared, V>, at member: Slingshot.Member<L, \(raw: name)>) -> Slingshot.Freer<L.Local, V> {
                // the proof says L is in the set of just \(raw: name), so L is \(raw: name)
                Slingshot.unsafeReinterpret(program, as: Slingshot.Freer<L.Local, V>.self)
            }
            """,
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

                \(raw: access)func callAsFunction<V: ~Copyable>(_ v: consuming Slingshot.At<\(raw: name), V>) -> V {
                    v.take()
                }

                \(raw: access)func callAsFunction<S: Includes, V: ~Copyable>(_ v: consuming Slingshot.At<S, V>) -> V {
                    v.take()
                }

                \(raw: access)func callAsFunction<S: Includes, V: ~Copyable>(_ facets: consuming Slingshot.Faceted<S, V>) -> V {
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
            /// Runs local code at \(raw: name), reading its facet of `facets` in place: for a noncopyable facet, like its
            /// session among a set's. `S` includes \(raw: name), so no membership proof is needed.
            \(raw: access)static func locally<Effs: Slingshot.Choreography.Has, S: Includes, Borrowed: ~Copyable, Output: ~Copyable>(
                borrowing facets: borrowing Slingshot.Faceted<S, Borrowed>,
                _ body: (Reader, borrowing Borrowed) throws -> Slingshot.Freer<Local, Output>
            ) -> Slingshot.Freer<Effs, Slingshot.At<\(raw: name), Output>> {
                Slingshot.Choreography.locally(borrowing: facets, of: member(of: S.self), body)
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
        let labels = members.map { member in
            let last = member.split(separator: ".").last.map(String.init) ?? member
            return last.prefix(1).lowercased() + last.dropFirst()
        }
        var seenLabels: Set<String> = []
        for (member, label) in zip(members, labels) where !seenLabels.insert(label).inserted {
            throw effectError("\(member) would have the same label as another member in faceted(\(label):): rename one of them", at: set.name)
        }
        let facetedParameters = zip(members, labels).map { "\($1): consuming Slingshot.At<\($0), V>" }.joined(separator: ", ")
        // each member's value joins the facets where it's held: at most one is held at any node
        let facetedAdditions = labels.map { "._unchecked(adding: \($0))" }.joined()
        let constantParameters = labels.map { "\($0): V" }.joined(separator: ", ")
        // each constant becomes a value at its member, then they're faceted like held values
        let heldArguments = labels.map { "\($0): \($0)Held" }.joined(separator: ", ")
        let constantsProgram = Array(zip(zip(members, labels), members.indices)).reversed().reduce("\(name).faceted(\(heldArguments))") { inner, element in
            let ((member, label), index) = element
            let combinator = index == members.count - 1 ? "map" : "flatMap"
            return "Slingshot.Choreography.constant(\(label), at: \(member).self).\(combinator) { \(label)Held in \(inner) }"
        }
        let containers = members.map { "\($0).Includes" }.joined(separator: " & ")
        // Hoisting into each member's Local is what checks that every member has the shared families
        let lifts = members.map { member in
            """
                if L.self == \(member).self {
                    return Slingshot.unsafeReinterpret(Shared.hoist(program, into: \(member).Local.self), as: Slingshot.Freer<L.Local, V>.self)
                }
            """
        }.joined(separator: "\n")
        let shared: [DeclSyntax] = declaresTypealias("Shared", in: set) ? [
            """
            /// Fails to compile unless `Shared` is an effect stack: write `SomeFamily.Family` for a family on its own.
            private typealias SharedIsAnEffectStack = Slingshot.EffectStackCheck<Shared>
            """,
        ] : [
            """
            /// \(raw: name)'s `parallel` bodies are pure: declare `typealias Shared = SomeStack` for shared effects.
            \(raw: access)typealias Shared = Slingshot.NoEffects
            """,
        ]
        return shared + [
            """
            /// One value per member, as \(raw: name)'s facets: each member's facet is its own value. Nothing is sent,
            /// and nothing says the values are equal.
            \(raw: access)static func faceted<V: ~Copyable>(\(raw: facetedParameters)) -> Slingshot.Faceted<\(raw: name), V> {
                Slingshot.Faceted<\(raw: name), V>.absent\(raw: facetedAdditions)
            }
            """,
            """
            /// One constant per member, as \(raw: name)'s facets: each member makes its own constant locally.
            \(raw: access)static func faceted<Effs: Slingshot.Choreography.Has, V>(\(raw: constantParameters)) -> Slingshot.Freer<Effs, Slingshot.Faceted<\(raw: name), V>> {
                \(raw: constantsProgram)
            }
            """,
            """
            /// A program in \(raw: name)'s shared effects, as the local program of the member running it.
            /// Only compiles when each member's `Local` has all of `Shared`'s families.
            \(raw: access)static func lift<L: Slingshot.Location, V: ~Copyable>(_ program: consuming Slingshot.Freer<Shared, V>, at member: Slingshot.Member<L, \(raw: name)>) -> Slingshot.Freer<L.Local, V> {
            \(raw: lifts)
                preconditionFailure("\\(L.self) has a proof of membership in \(raw: name) without being one of its members")
            }
            """,
            """
            /// Each member's proof of membership, by name: a `Quire<\(raw: name), V>` reads \(raw: labels.map { "`quire.\($0)`" }.joined(separator: ", ")).
            \(raw: access)struct Members {
            \(raw: zip(members, labels).map { "    \(access)var `\($1)`: Slingshot.Member<\($0), \(name)> { Slingshot.Member(_unchecked: ()) }" }.joined(separator: "\n"))
            }
            """,
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

/// Whether the enum declares a typealias with this name itself, which the macros then don't generate
private func declaresTypealias(_ name: String, in declaration: EnumDeclSyntax) -> Bool {
    declaration.memberBlock.members.contains { member in
        member.decl.as(TypeAliasDeclSyntax.self)?.name.text == name
    }
}
