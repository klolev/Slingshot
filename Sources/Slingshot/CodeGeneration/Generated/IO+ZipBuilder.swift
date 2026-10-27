@resultBuilder
public enum IOZipBuilder {
    public static func buildBlock<each T>(_ components: repeat IO<each T>) -> IO<(repeat each T)> {
        var erased: [IO<Any>] = []
        for component in repeat each components {
            erased.append(component.map { $0 as Any })
        }
        return IO<Any>.traverse(erased) { $0 }.map { makeTuple($0) }
    }
}

public extension IO {
    /// Combines the block's statements into one IO of a tuple of their values.
    static func zip(@IOZipBuilder _ body: () -> Self) -> Self {
        body()
    }
}