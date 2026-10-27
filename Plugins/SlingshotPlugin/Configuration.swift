struct Configuration: Decodable {
    let protocols: [ProtocolMetadata]
    let structs: [StructMetadata]
    let templates: [TemplateMetadata]

    struct TemplateMetadata: Decodable {
        enum TemplateType: String, Decodable {
            case containerStruct, protocolExtension, traversable, traversableNonEmpty, zipBuilder
        }

        let name: String
        let applyOn: [String]
        let type: TemplateType
    }
    
    struct StructMetadata: Decodable {
        enum StructType: String, Decodable {
            case generic
            case concrete
        }

        struct Conformance: Decodable {
            let name: String
            let `where`: String?
        }

        struct ApplicativeMetadata: Decodable {
            let innerParam: String
            let `protocol`: String?
            let witnessKeypath: String?
            /// The applicative runs its effects concurrently, so traversals need Sendable transforms and elements
            let sendable: Bool?
            /// The applicative stops at its first failure, so a concurrent traversal into it can cancel the work after that failure
            let shortCircuits: Bool?
        }

        let name: String
        let type: StructType
        let arguments: [String]?
        let elements: String?
        let applicative: ApplicativeMetadata?
        let elementConstraints: [String]?
        let conformances: [Conformance]
    }
    
    func get(structMetadata: String) -> StructMetadata? {
        structs.first(where: { $0.name == structMetadata })
    }
    
    func get(protocolMetadata: String) -> ProtocolMetadata? {
        protocols.first(where: { $0.name == protocolMetadata })
    }
    
    func get(templateMetadata: String) -> TemplateMetadata? {
        templates.first(where: { $0.name == templateMetadata })
    }
}
