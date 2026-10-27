import Foundation

struct TraversableNonEmptyTemplate: Template {
    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        let element = type.elements ?? type.arguments?.first ?? ""

        let applicatives = configuration.structs.filter { $0.applicative != nil }

        let extensions = applicatives.map { functor in
            generateTraverse(container: type, element: element, functor: functor)
        }

        let contents = extensions.joined(separator: "\n\n")

        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }

    private func generateTraverse(container: Configuration.StructMetadata,
                                  element: String,
                                  functor: Configuration.StructMetadata) -> String {
        let applicative = functor.applicative!
        let allArgs = functor.arguments ?? []
        let freeParams = allArgs.filter { $0 != applicative.innerParam }

        let outputContainerType = container.type == .concrete
            ? container.name
            : "\(container.name)<T>"
        let outputNonEmptyType = "\(outputContainerType).NonEmpty"

        let genericParams: String
        if freeParams.isEmpty {
            genericParams = "<T>"
        } else {
            genericParams = "<T, \(freeParams.joined(separator: ", "))>"
        }

        func applyFunctor(_ innerType: String) -> String {
            if functor.type == .concrete {
                return "\(functor.name)<\(innerType)>"
            } else {
                let args = allArgs.map { $0 == applicative.innerParam ? innerType : $0 }
                return "\(functor.name)<\(args.joined(separator: ", "))>"
            }
        }

        let transformReturn = applyFunctor("T")
        let returnFunctorType = applyFunctor(outputNonEmptyType)

        return """
        public extension \(container.name).NonEmpty {
            func traverse\(genericParams)(_ transform: @escaping (\(element)) -> \(transformReturn)) -> \(returnFunctorType) {
                let elements = container.isEmpty ? [first] : Array(container)
                // A non-empty input always yields a non-empty output
                return \(transformReturn).traverse(elements, transform).map { \(outputNonEmptyType)(container: \(outputContainerType)($0))! }
            }
        }
        """
    }
}
