@resultBuilder
public enum EitherZipBuilder {
    public static func buildBlock<each T, L>(_ components: repeat Either<L, each T>) -> Either<L, (repeat each T)> {
        var erased: [Either<L, Any>] = []
        for component in repeat each components {
            erased.append(component.map { $0 as Any })
        }
        return Either<L, Any>.traverse(erased) { $0 }.map { makeTuple($0) }
    }
}

public extension Either {
    /// Combines the block's statements into one Either of a tuple of their values.
    static func zip(@EitherZipBuilder _ body: () -> Self) -> Self {
        body()
    }
}