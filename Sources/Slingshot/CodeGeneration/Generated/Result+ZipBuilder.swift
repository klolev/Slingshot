@resultBuilder
public enum ResultZipBuilder {
    public static func buildBlock<each T, Failure>(_ components: repeat Result<each T, Failure>) -> Result<(repeat each T), Failure> {
        var erased: [Result<Any, Failure>] = []
        for component in repeat each components {
            erased.append(component.map { $0 as Any })
        }
        return Result<Any, Failure>.traverse(erased) { $0 }.map { makeTuple($0) }
    }
}

public extension Result {
    /// Combines the block's statements into one Result of a tuple of their values.
    static func zip(@ResultZipBuilder _ body: () -> Self) -> Self {
        body()
    }
}