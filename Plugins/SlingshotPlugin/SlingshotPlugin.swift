import Foundation
import PackagePlugin

@main
struct SlingshotPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let input = context.package.directory.appending(["Sources", "Slingshot", "CodeGeneration"])
        let output = URL(filePath: input.appending("Generated").string)
        let configurationURL = URL(filePath: input.appending("config.json").string)
        let configuration = try JSONDecoder().decode(Configuration.self, from: try .init(contentsOf: configurationURL))
        
        try configuration.templates
            .flatMap { templateMetadata in
                guard let template = Self.templates[templateMetadata.type] else {
                    return Array<(String, String)>()
                }
                
                return try templateMetadata.applyOn
                    .compactMap(configuration.get(structMetadata:))
                    .map {
                        try template.generate(templateMetadata.name,
                                              for: $0,
                                              with: configuration,
                                              inRootPath: URL(filePath: input.appending(["Templates",
                                                                                         templateMetadata.name]).string))
                    }
            }
            .forEach { (entry: (name: String, contents: String)) in
                guard let data = entry.contents.data(using: .utf8) else {
                    throw CodeGenerationError.invalidData
                }
                
                try data.write(to: output.appending(component: entry.name), options: .atomic)
            }
    }
    
    enum CodeGenerationError: Error {
        case invalidArguments
        case invalidData
    }
    
    private static let templates: [Configuration.TemplateMetadata.TemplateType: Template] = [
        .containerStruct: ContainerStructTemplate(),
        .protocolExtension: ProtocolExtensionTemplate(),
        .traversable: TraversableTemplate(),
        .traversableNonEmpty: TraversableNonEmptyTemplate(),
        .zipBuilder: ZipBuilderTemplate()
    ]
}
