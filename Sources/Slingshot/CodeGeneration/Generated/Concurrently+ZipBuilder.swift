@resultBuilder
public enum ConcurrentlyZipBuilder {
    public static func buildBlock<each T: Sendable>(_ components: repeat Concurrently<each T>) -> Concurrently<(repeat each T)> {
        var erased: [Concurrently<any Sendable>] = []
        for component in repeat each components {
            erased.append(component.map { $0 as any Sendable })
        }
        return Concurrently<any Sendable>.traverse(erased) { $0 }.map { makeTuple($0) }
    }
}

public extension Concurrently {
    /// Combines the block's statements into one Concurrently of a tuple of their values.
    static func zip(@ConcurrentlyZipBuilder _ body: () -> Self) -> Self {
        body()
    }
}