import Foundation

/// Generates the `Binder` overload that lets `#do` bind a type: inside a block of that type, a bind takes
/// the same type with only its bound value free, like `>>=`'s `m a -> (a -> m b) -> m b` in Haskell.
/// Everything else, like `Result`'s `Failure`, comes from the block, so constructors inside a bind infer it.
struct DoBinderTemplate: Template {
    enum Error: Swift.Error, CustomStringConvertible {
        case concrete(String)
        case unknownBound(String)

        var description: String {
            switch self {
            case .concrete(let name):
                "DoBinder needs a generic type, but \(name) is declared concrete: it has no value to bind."
            case .unknownBound(let name):
                "DoBinder can't tell which of \(name)'s type arguments a bind produces: set its \"bound\"."
            }
        }
    }

    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        guard type.type == .generic, let arguments = type.arguments, !arguments.isEmpty else {
            throw Error.concrete(type.name)
        }
        guard let bound = type.boundParam, arguments.contains(bound) else {
            throw Error.unknownBound(type.name)
        }

        let fresh = "X"
        // A Sendable applicative needs Sendable values, and a container its elements' constraints
        let noncopyable = type.noncopyable == true
        let constraints = (type.applicative?.sendable == true ? ["Sendable"] : []) + (type.elementConstraints ?? [])
            + (noncopyable ? ["~Copyable"] : [])
        func constrained(_ name: String) -> String {
            constraints.isEmpty ? name : "\(name): \(constraints.joined(separator: " & "))"
        }

        /// The type wrapped around `inner` in place of its bound value, e.g. `Result<inner, Failure>`
        func rebound(_ inner: String) -> String {
            "\(type.name)<\(arguments.map { $0 == bound ? inner : $0 }.joined(separator: ", "))>"
        }

        let blockType = rebound(bound)
        let method: String
        if type.name == "Optional" {
            // Swift promotes any value to an Optional parameter, so a protocol keeps `bind(3)` from compiling
            method = """
                func callAsFunction<\(bound), Arg: OptionalProtocol>(_ m: Arg) -> Arg.Wrapped where M == \(blockType) {
                    fatalError("bind only works inside #do")
                }
            """
        } else {
            let genericParams = arguments.map { $0 == bound ? constrained($0) : $0 } + [constrained(fresh)]
            method = """
                func callAsFunction<\(genericParams.joined(separator: ", "))>(_ m: \(noncopyable ? "consuming " : "")\(rebound(fresh))) -> \(fresh) where M == \(blockType) {
                    fatalError("bind only works inside #do")
                }
            """
        }

        let contents = """
        #if Macros
        public extension Binder\(noncopyable ? " where M: ~Copyable" : "") {
            /// Binds inside a #do block of type \(type.name), where a bind can only differ from the block in its `\(bound)`.
        \(method)
        }
        #endif
        """
        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }
}

extension Configuration.StructMetadata {
    /// The type argument a `#do` bind produces: set explicitly, or the applicative's, or the only argument
    var boundParam: String? {
        bound ?? applicative?.innerParam ?? (arguments?.count == 1 ? arguments?.first : nil)
    }
}
