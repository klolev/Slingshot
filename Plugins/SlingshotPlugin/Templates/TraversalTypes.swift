import Foundation

/// Builds the type names used by the Traversable templates when traversing `container` into `functor`.
struct TraversalTypes {
    enum Error: Swift.Error, CustomStringConvertible {
        case concrete(String)
        case missingArguments(String)
        case singleValueContainer(String)

        var description: String {
            switch self {
            case .concrete(let name):
                "Traversable needs generic types, but \(name) is declared concrete: it can't be rebuilt around a new element type."
            case .missingArguments(let name):
                "Traversable needs \(name) to declare its type arguments."
            case .singleValueContainer(let name):
                "Traversable is for collections, but \(name) holds a single value: write its traverse by hand, like Optional_Traversable.swift."
            }
        }
    }

    /// The container's element type parameter, e.g. `Element`
    let element: String
    private let container: Configuration.StructMetadata
    private let functor: Configuration.StructMetadata
    private let applicative: Configuration.StructMetadata.ApplicativeMetadata

    init(container: Configuration.StructMetadata, functor: Configuration.StructMetadata) throws {
        for type in [container, functor] {
            guard type.type == .generic else { throw Error.concrete(type.name) }
            guard type.arguments?.isEmpty == false else { throw Error.missingArguments(type.name) }
        }
        guard container.applicative == nil else { throw Error.singleValueContainer(container.name) }

        self.element = container.arguments![0]
        self.container = container
        self.functor = functor
        self.applicative = functor.applicative!
    }

    /// The functor's type parameters other than the one it wraps, e.g. `Failure` for `Result`
    var freeParams: [String] {
        functor.arguments!.filter { $0 != applicative.innerParam }
    }

    /// Generic parameters for `traverse`: `T` followed by the functor's free parameters
    var genericParams: String {
        "<\((["T"] + freeParams).joined(separator: ", "))>"
    }

    /// Pairs of a Sendable applicative with a short-circuiting one, e.g. `Concurrently` with `Either`,
    /// whose composition gets a `traverse` that cancels the work after the first failure
    static func shortCircuitingPairs(in configuration: Configuration) -> [(outer: Configuration.StructMetadata, inner: Configuration.StructMetadata)] {
        let applicatives = configuration.structs.filter { $0.applicative != nil }
        let outers = applicatives.filter { $0.applicative?.sendable == true }
        let inners = applicatives.filter { $0.applicative?.shortCircuits == true }
        return outers.flatMap { outer in inners.map { inner in (outer, inner) } }
    }

    /// Attributes for the `transform` parameter of `traverse`
    var transformAttributes: String {
        applicative.sendable == true ? "@escaping @Sendable" : "@escaping"
    }

    /// The `where` clause `traverse` needs on the container, e.g. ` where Element: Sendable`
    var traverseWhereClause: String {
        applicative.sendable == true ? " where \(element): Sendable" : ""
    }

    /// The container rebuilt around `inner`, e.g. `Set<inner>`
    func container(of inner: String) -> String {
        let args = container.arguments!.map { $0 == element ? inner : $0 }
        return "\(container.name)<\(args.joined(separator: ", "))>"
    }

    /// The functor wrapped around `inner`, e.g. `Result<inner, Failure>`.
    /// When `qualifier` is given, free parameters are read from it, e.g. `Element.Failure`.
    func functor(of inner: String, qualifier: String? = nil) -> String {
        let args = functor.arguments!.map { arg in
            if arg == applicative.innerParam { return inner }
            return qualifier.map { "\($0).\(arg)" } ?? arg
        }
        return "\(functor.name)<\(args.joined(separator: ", "))>"
    }
}
