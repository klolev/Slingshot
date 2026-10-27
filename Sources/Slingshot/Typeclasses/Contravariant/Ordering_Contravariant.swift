public extension Ordering {
    /// Orders other values by what `transform` gives for them
    func contramap<U>(_ transform: @escaping (U) -> T) -> Ordering<U> {
        Ordering<U> { compare(transform($0), transform($1)) }
    }
}
