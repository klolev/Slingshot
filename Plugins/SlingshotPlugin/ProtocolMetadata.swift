import Foundation

struct ProtocolMetadata: Decodable {
    let name: String
    let properties: [Property]
    let associatedTypes: [String]?
    
    struct Property {
        struct Argument {
            let label: String?
            let name: String
            let type: String
            let isMutable: Bool
            
            init(label: String? = nil, _ name: String, _ type: String, isMutable: Bool = false) {
                self.label = label
                self.name = name
                self.type = type
                self.isMutable = isMutable
            }
            
            var signature: String {
                let mutability = isMutable ? "inout " : ""
                if let label {
                    return "\(label) \(name): \(mutability)\(type)"
                } else {
                    return "\(name): \(mutability)\(type)"
                }
            }
            
            func call(with value: String) -> String {
                let value = isMutable ? "&\(value)" : value
                if let label {
                    return label == "_" ? value : "\(label): \(value)"
                } else {
                    return "\(name): \(value)"
                }
            }
            
            func call(subscriptWith value: String) -> String {
                if let label, label != "_" {
                    "\(label): \(value)"
                } else {
                    value
                }
            }
        }
        
        struct Operator {
            let name: String
            let lhs: String
            let rhs: String
        }
        
        struct Method {
            let name: String
            let arguments: [Argument]
            let isStatic: Bool
        }
        
        struct Variable {
            enum Accessor {
                case get, set, didSet, willSet
            }
            
            let name: String
            let accessors: Set<Accessor>
            let isStatic: Bool
        }
        
        struct Subscript {
            let arguments: [Argument]
        }
        
        enum PropertyType {
            case `operator`(Operator)
            case method(Method)
            case variable(Variable)
            case `subscript`(Subscript)
            
            func signature(returnType: String) -> String {
                switch self {
                case .operator(let `operator`):
                    "static func \(`operator`.name) (lhs: \(`operator`.lhs), rhs: \(`operator`.rhs)) -> \(returnType)"
                case .method(let method):
                    "\(method.isStatic ? "static " : "")func \(method.name)(\(method.arguments.map(\.signature).joined(separator: ", "))) -> \(returnType)"
                case .variable(let variable):
                    "\(variable.isStatic ? "static " : "")var \(variable.name): \(returnType)"
                case .subscript(let `subscript`):
                    "subscript(\(`subscript`.arguments.map(\.signature).joined(separator: ", "))) -> \(returnType)"
                }
            }
            
            func call(through keypath: String) -> String {
                switch self {
                case .operator(let `operator`):
                    "lhs.\(keypath) \(`operator`.name) rhs.\(keypath)"
                case .method(let method):
                    "\(method.isStatic ? "Self" : "self").\(keypath).\(method.name)(\(method.arguments.map { $0.call(with: $0.name) }.joined(separator: ", ")))"
                case .variable(let variable):
                    "\(variable.isStatic ? "Self" : "self").\(keypath).\(variable.name)"
                case .subscript(let `subscript`):
                    "self.\(keypath)[\(`subscript`.arguments.map { $0.call(subscriptWith: $0.name) }.joined(separator: ", "))]"
                }
            }
        }
        
        let type: PropertyType
        let returnType: String
        
        init(type: PropertyType, returnType: String = "Void") {
            self.type = type
            self.returnType = returnType
        }
        
        static func method(_ name: String,
                           isStatic: Bool = false,
                           args: [Argument] = [],
                           returns: String = "Void") -> Self {
            .init(type: .method(.init(name: name, arguments: args, isStatic: isStatic)), returnType: returns)
        }
        
        static func variable(_ name: String,
                             isStatic: Bool = false,
                             type: String) -> Self {
            .init(type: .variable(.init(name: name, accessors: [], isStatic: isStatic)), returnType: type)
        }
        
        static func `subscript`(args: [Argument], returns: String) -> Self {
            .init(type: .subscript(.init(arguments: args)), returnType: returns)
        }
        
        static func `operator`(_ name: String, lhs: String, rhs: String, returns: String) -> Self {
            .init(type: .operator(.init(name: name, lhs: lhs, rhs: rhs)), returnType: returns)
        }
        
        var signature: String {
            "public " + type.signature(returnType: returnType)
        }
        
        func call(through keypath: String) -> String {
            type.call(through: keypath)
        }
    }
    
    func extend(_ typeName: String, through keypath: String, ofType type: String, where whereClause: String?) -> String {
        let whereClause = whereClause.map { "where \($0) " } ?? ""
        let associatedTypesAssignation = (associatedTypes ?? [])
            .map { "\tpublic typealias \($0) = \(type).\($0)" }
        
        let implementation = properties
            .map { "\t\($0.signature) { \($0.call(through: keypath)) }" }
        
        let lines = (associatedTypesAssignation + implementation).joined(separator: "\n")
        
        return "extension \(typeName): \(name) \(whereClause){\n\(lines)\n}"
    }
}

extension ProtocolMetadata.Property: Decodable {
    enum DecodingError: Error {
        case invalidString(String)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let isStatic = value.starts(with: "static")
        // Locals rather than globals: Regex isn't Sendable
        let functionRegex = #/(func (?<functionName>\S+) ?|subscript)\(.*\)( -> (?<returnType>[A-Za-z.<>?]+))?/#
        let argsRegex = #/((?<argumentLabel>\w+) )?(?<argument>\w+): ((?<isMutable>inout) )?(?<argumentType>[A-Za-z0-9.]+)(, )?/#
        let variableRegex = #/var (?<variableName>\w+): (?<variableType>[A-Za-z0-9.]+)/#

        if let match = try variableRegex.firstMatch(in: value) {
            self = .variable(String(match.output.variableName),
                             isStatic: isStatic,
                             type: String(match.output.variableType))
        } else if let match = try functionRegex.firstMatch(in: value) {
            let arguments = value.matches(of: argsRegex)
                .map {
                    ProtocolMetadata.Property.Argument(label: $0.output.argumentLabel.map(String.init),
                                                       String($0.output.argument),
                                                       String($0.output.argumentType),
                                                       isMutable: $0.output.isMutable != nil)
                }
            
            let returnType = match.output.returnType.map(String.init) ?? "Void"
            
            if let name = match.output.functionName.map(String.init) {
                if CharacterSet(charactersIn: name).isSubset(of: .alphanumerics) {
                    self = .method(name, isStatic: isStatic, args: arguments, returns: returnType)
                } else {
                    self = .operator(name, lhs: arguments[0].type, rhs: arguments[1].type, returns: returnType)
                }
            } else {
                self = .subscript(args: arguments, returns: returnType)
            }
        } else {   
            throw DecodingError.invalidString(value)
        }
    }
}
