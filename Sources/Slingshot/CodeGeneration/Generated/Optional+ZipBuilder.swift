@resultBuilder
public enum OptionalZipBuilder {
    public static func buildBlock<each T>(_ components: repeat Optional<each T>) -> Optional<(repeat each T)> {
        var erased: [Optional<Any>] = []
        for component in repeat each components {
            erased.append(component.map { $0 as Any })
        }
        return Optional<Any>.traverse(erased) { $0 }.map { makeTuple($0) }
    }
}

public extension Optional {
    /// Combines the block's statements into one Optional of a tuple of their values.
    static func zip(@OptionalZipBuilder _ body: () -> Self) -> Self {
        body()
    }
}