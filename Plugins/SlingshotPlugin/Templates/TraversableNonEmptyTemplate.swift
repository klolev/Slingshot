import Foundation

struct TraversableNonEmptyTemplate: Template {
    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        let applicatives = configuration.structs.filter { $0.applicative != nil }

        let extensions = try applicatives.map { functor in
            try generateTraverse(container: type, functor: functor)
        }

        let contents = extensions.joined(separator: "\n\n")

        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }

    private func generateTraverse(container: Configuration.StructMetadata,
                                  functor: Configuration.StructMetadata) throws -> String {
        let types = try TraversalTypes(container: container, functor: functor)
        let transformReturn = types.functor(of: "T")
        let outputContainerType = types.container(of: "T")
        let outputNonEmptyType = "\(outputContainerType).NonEmpty"

        return """
        public extension \(container.name).NonEmpty {
            func traverse\(types.genericParams)(_ transform: @escaping (\(types.element)) -> \(transformReturn)) -> \(types.functor(of: outputNonEmptyType)) {
                let elements = container.isEmpty ? [first] : Array(container)
                // A non-empty input always yields a non-empty output
                return \(transformReturn).traverse(elements, transform).map { \(outputNonEmptyType)(container: \(outputContainerType)($0))! }
            }
        }
        """
    }
}
