// `zip` result builders, generated per applicative from the ZipBuilder template:
//
//     Concurrently.zip {
//         fetchUser(id)       // all run concurrently
//         fetchConfig()
//     }
//     .map { user, config in render(user, config) }
//
// The statements are combined with the applicative's own `traverse`, so each zip behaves like that type does:
// concurrent (and scheduled by `Strategy`) for Concurrently, collecting every error for Validation,
// stopping at the first failure for Optional, Result and Either, and one after another for IO.
// Unlike `#do`, later statements can't use earlier results; that needs a monad.

/// Rebuilds a tuple from the type-erased values a zip builder traversed, in order
func makeTuple<Element, each T>(_ values: [Element]) -> (repeat each T) {
    var index = 0
    func next<V>(_: V.Type) -> V {
        defer { index += 1 }
        // The builder erased exactly these types, in this order
        return values[index] as! V
    }
    return (repeat next((each T).self))
}
