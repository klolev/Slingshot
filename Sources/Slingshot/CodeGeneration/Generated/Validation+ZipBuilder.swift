@resultBuilder
public enum ValidationZipBuilder {
    public static func buildBlock<each T, Failure>(_ components: repeat Validation<Failure, each T>) -> Validation<Failure, (repeat each T)> {
        var erased: [Validation<Failure, Any>] = []
        for component in repeat each components {
            erased.append(component.map { $0 as Any })
        }
        return Validation<Failure, Any>.traverse(erased) { $0 }.map { makeTuple($0) }
    }
}

public extension Validation {
    /// Combines the block's statements into one Validation of a tuple of their values.
    static func zip(@ValidationZipBuilder _ body: () -> Self) -> Self {
        body()
    }
}