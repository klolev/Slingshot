import Foundation

struct TraversableTemplate: Template {
    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        let element = type.elements ?? type.arguments?.first ?? ""

        let applicatives = configuration.structs.filter { $0.applicative != nil }

        let traverseExtensions = applicatives.map { functor in
            generateTraverse(container: type, element: element, functor: functor)
        }

        let sequencedExtensions = applicatives.compactMap { functor in
            generateSequenced(container: type, element: element, functor: functor)
        }

        let contents = (traverseExtensions + sequencedExtensions).joined(separator: "\n\n")

        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }

    private func generateTraverse(container: Configuration.StructMetadata,
                                  element: String,
                                  functor: Configuration.StructMetadata) -> String {
        let applicative = functor.applicative!
        let allArgs = functor.arguments ?? []
        let freeParams = allArgs.filter { $0 != applicative.innerParam }

        let outputContainerType: String
        if container.applicative != nil {
            outputContainerType = "\(container.name)<T>"
        } else if container.type == .concrete {
            outputContainerType = container.name
        } else {
            outputContainerType = "\(container.name)<T>"
        }

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
        let returnFunctorType = applyFunctor(outputContainerType)

        if container.applicative != nil {
            return generateFunctorTraverse(
                container: container, element: element,
                genericParams: genericParams, transformReturn: transformReturn,
                returnFunctorType: returnFunctorType, outputContainerType: outputContainerType)
        } else {
            return generateFoldableTraverse(
                container: container, element: element,
                genericParams: genericParams, transformReturn: transformReturn,
                returnFunctorType: returnFunctorType, outputContainerType: outputContainerType)
        }
    }

    private func generateFoldableTraverse(
        container: Configuration.StructMetadata, element: String,
        genericParams: String, transformReturn: String,
        returnFunctorType: String, outputContainerType: String) -> String {
        """
        public extension \(container.name) {
            func traverse\(genericParams)(_ transform: @escaping (\(element)) -> \(transformReturn)) -> \(returnFunctorType) {
                \(transformReturn).traverse(self, transform).map { \(outputContainerType)($0) }
            }
        }
        """
    }

    private func generateFunctorTraverse(
        container: Configuration.StructMetadata, element: String,
        genericParams: String, transformReturn: String,
        returnFunctorType: String, outputContainerType: String) -> String {
        let innerParam = container.applicative!.innerParam
        return """
        public extension \(container.name) {
            func traverse\(genericParams)(_ transform: @escaping (\(innerParam)) -> \(transformReturn)) -> \(returnFunctorType) {
                switch self {
                case .some(let x):
                    return transform(x).map(\(outputContainerType).some)
                case .none:
                    return .pure(.none)
                }
            }
        }
        """
    }

    private func generateSequenced(container: Configuration.StructMetadata,
                                   element: String,
                                   functor: Configuration.StructMetadata) -> String? {
        guard let applicative = functor.applicative,
              let protocolName = applicative.protocol,
              let witnessKeypath = applicative.witnessKeypath else {
            return nil
        }

        let allArgs = functor.arguments ?? []

        let constraintTarget: String
        let assocPrefix: String
        if let containerApplicative = container.applicative {
            constraintTarget = containerApplicative.innerParam
            assocPrefix = containerApplicative.innerParam
        } else {
            constraintTarget = "Element"
            assocPrefix = "Element"
        }

        let outputContainerType: String
        if container.applicative != nil {
            outputContainerType = "\(container.name)<\(assocPrefix).\(applicative.innerParam)>"
        } else if container.type == .concrete {
            outputContainerType = container.name
        } else {
            outputContainerType = "\(container.name)<\(assocPrefix).\(applicative.innerParam)>"
        }

        func applyFunctor(_ innerType: String) -> String {
            if functor.type == .concrete {
                return "\(functor.name)<\(innerType)>"
            } else {
                let args = allArgs.map {
                    $0 == applicative.innerParam ? innerType : "\(assocPrefix).\($0)"
                }
                return "\(functor.name)<\(args.joined(separator: ", "))>"
            }
        }

        let returnType = applyFunctor(outputContainerType)

        let extraConstraints = (container.elementConstraints ?? []).map { constraint in
            ", \(assocPrefix).\(applicative.innerParam): \(constraint)"
        }.joined()

        return """
        public extension \(container.name) where \(constraintTarget): \(protocolName)\(extraConstraints) {
            var sequenced: \(returnType) {
                traverse(\\.\(witnessKeypath))
            }
        }
        """
    }
}
