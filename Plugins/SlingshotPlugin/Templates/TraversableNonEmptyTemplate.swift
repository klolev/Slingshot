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

        let shortCircuitingExtensions = try TraversalTypes.shortCircuitingPairs(in: configuration).map { pair in
            try generateShortCircuitingTraverse(container: type, outer: pair.outer, inner: pair.inner)
        }

        let contents = (extensions + shortCircuitingExtensions).joined(separator: "\n\n")

        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }

    private func generateTraverse(container: Configuration.StructMetadata,
                                  functor: Configuration.StructMetadata) throws -> String {
        let types = try TraversalTypes(container: container, functor: functor)
        let transformReturn = types.functor(of: "T")
        let outputContainerType = types.container(of: "T")
        let outputNonEmptyType = "\(outputContainerType).NonEmpty"

        return """
        public extension \(container.name).NonEmpty\(types.traverseWhereClause) {
            func traverse\(types.genericParams)(_ transform: \(types.transformAttributes) (\(types.element)) -> \(transformReturn)) -> \(types.functor(of: outputNonEmptyType)) {
                let elements = container.isEmpty ? [first] : Array(container)
                // A non-empty input always yields a non-empty output
                return \(transformReturn).traverse(elements, transform).map { \(outputNonEmptyType)(container: \(outputContainerType)($0))! }
            }
        }
        """
    }

    private func generateShortCircuitingTraverse(container: Configuration.StructMetadata,
                                                 outer: Configuration.StructMetadata,
                                                 inner: Configuration.StructMetadata) throws -> String {
        let outerTypes = try TraversalTypes(container: container, functor: outer)
        let innerTypes = try TraversalTypes(container: container, functor: inner)
        let genericParams = "<\((["T"] + outerTypes.freeParams + innerTypes.freeParams).joined(separator: ", "))>"
        let transformReturn = outerTypes.functor(of: innerTypes.functor(of: "T"))
        let outputContainerType = innerTypes.container(of: "T")
        let outputNonEmptyType = "\(outputContainerType).NonEmpty"

        return """
        public extension \(container.name).NonEmpty\(outerTypes.traverseWhereClause) {
            func traverse\(genericParams)(_ transform: \(outerTypes.transformAttributes) (\(innerTypes.element)) -> \(transformReturn)) -> \(outerTypes.functor(of: innerTypes.functor(of: outputNonEmptyType))) {
                let elements = container.isEmpty ? [first] : Array(container)
                // A non-empty input always yields a non-empty output
                return \(outerTypes.functor(of: "T")).traverse(elements, transform).map { $0.map { \(outputNonEmptyType)(container: \(outputContainerType)($0))! } }
            }
        }
        """
    }
}
