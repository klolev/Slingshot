import Foundation

struct TraversableTemplate: Template {
    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        let applicatives = configuration.structs.filter { $0.applicative != nil }

        let traverseExtensions = try applicatives.map { functor in
            try generateTraverse(container: type, functor: functor)
        }

        let sequencedExtensions = try applicatives.compactMap { functor in
            try generateSequenced(container: type, functor: functor)
        }

        let contents = (traverseExtensions + sequencedExtensions).joined(separator: "\n\n")

        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }

    private func generateTraverse(container: Configuration.StructMetadata,
                                  functor: Configuration.StructMetadata) throws -> String {
        let types = try TraversalTypes(container: container, functor: functor)
        let transformReturn = types.functor(of: "T")
        let outputContainerType = types.container(of: "T")

        return """
        public extension \(container.name) {
            func traverse\(types.genericParams)(_ transform: @escaping (\(types.element)) -> \(transformReturn)) -> \(types.functor(of: outputContainerType)) {
                \(transformReturn).traverse(self, transform).map { \(outputContainerType)($0) }
            }
        }
        """
    }

    private func generateSequenced(container: Configuration.StructMetadata,
                                   functor: Configuration.StructMetadata) throws -> String? {
        guard let applicative = functor.applicative,
              let protocolName = applicative.protocol,
              let witnessKeypath = applicative.witnessKeypath else {
            return nil
        }

        let types = try TraversalTypes(container: container, functor: functor)
        let element = types.element
        let outputContainerType = types.container(of: "\(element).\(applicative.innerParam)")
        let returnType = types.functor(of: outputContainerType, qualifier: element)

        let extraConstraints = (container.elementConstraints ?? []).map { constraint in
            ", \(element).\(applicative.innerParam): \(constraint)"
        }.joined()

        return """
        public extension \(container.name) where \(element): \(protocolName)\(extraConstraints) {
            var sequenced: \(returnType) {
                traverse(\\.\(witnessKeypath))
            }
        }
        """
    }
}
