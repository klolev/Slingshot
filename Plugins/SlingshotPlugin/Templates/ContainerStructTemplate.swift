import Foundation

struct ContainerStructTemplate: Template {
    func generate(_ templateName: String,
                  for type: Configuration.StructMetadata,
                  with configuration: Configuration,
                  inRootPath rootPath: URL) throws -> (name: String, contents: String) {
        let templatePath = rootPath.appending(path: "\(templateName).swifttemplate")
        let template = String(data: try Data(contentsOf: templatePath), encoding: .utf8)!
        let typeArg = type.elements ?? type.arguments?.first ?? ""
        let args = [#"\(type)"#: type.name,
                    #"\(item)"#: typeArg,
                    #"\(fullyQualifiedType)"#: type.type == .concrete ? type.name : "\(type.name)<\(typeArg)>"]
        
        let contents = apply(template: template, with: args)
           .appending(type.conformances
            .compactMap { conformance in
                guard let protocolMetadata = configuration.get(protocolMetadata: conformance.name) else { return nil }
                let overloadPath = rootPath.appending(components: "Overloads", "\(conformance.name).swifttemplate")
                
                if let data = try? Data(contentsOf: overloadPath),
                   let overloadTemplate = String(data: data, encoding: .utf8) {
                    let whereClause = conformance.where.map { " where \($0)" } ?? ""
                    return apply(template: overloadTemplate, with: args.merging([#"\(whereClause)"#: whereClause]) { $1 })
                }
                
                
                return protocolMetadata.extend("\(type.name).\(templateName)",
                                               through: "container",
                                               ofType: type.name,
                                               where: conformance.where)
            }
           .joined(separator: "\n\n"))
        
        return (name: "\(type.name)+\(templateName).swift", contents: contents)
    }
    
    private func apply(template: String, with arguments: [String: String]) -> String {
        arguments.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
