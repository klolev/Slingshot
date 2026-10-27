import Foundation

/// Generates a `zip` result builder for an applicative. Its statements are type-erased, combined with the
/// applicative's own `traverse`, then cast back into a tuple, so the zip behaves exactly like that traversal.
struct ZipBuilderTemplate: Template {
    enum Error: Swift.Error, CustomStringConvertible {
        case notApplicative(String)

        var description: String {
            switch self {
            case .notApplicative(let name):
                "ZipBuilder needs a generic applicative, but \(name) has no applicative metadata."
            }
        }
    }

    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        guard type.type == .generic, let applicative = type.applicative, let arguments = type.arguments else {
            throw Error.notApplicative(type.name)
        }
        let sendable = applicative.sendable == true
        let builder = "\(type.name)ZipBuilder"
        let erased = sendable ? "any Sendable" : "Any"
        let freeParams = arguments.filter { $0 != applicative.innerParam }
        let genericParams = ([sendable ? "each T: Sendable" : "each T"] + freeParams).joined(separator: ", ")

        /// The applicative wrapped around `inner`, e.g. `Result<inner, Failure>`
        func functor(of inner: String) -> String {
            let args = arguments.map { $0 == applicative.innerParam ? inner : $0 }
            return "\(type.name)<\(args.joined(separator: ", "))>"
        }

        let contents = """
        @resultBuilder
        public enum \(builder) {
            public static func buildBlock<\(genericParams)>(_ components: repeat \(functor(of: "each T"))) -> \(functor(of: "(repeat each T)")) {
                var erased: [\(functor(of: erased))] = []
                for component in repeat each components {
                    erased.append(component.map { $0 as \(erased) })
                }
                return \(functor(of: erased)).traverse(erased) { $0 }.map { makeTuple($0) }
            }
        }

        public extension \(type.name) {
            /// Combines the block's statements into one \(type.name) of a tuple of their values.
            static func zip(@\(builder) _ body: () -> Self) -> Self {
                body()
            }
        }
        """
        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }
}
