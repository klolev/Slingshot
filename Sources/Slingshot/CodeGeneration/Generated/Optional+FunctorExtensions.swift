public extension Optional {
    func replace<C>(with x: C) -> Optional<C> {
        map(constant(x))
    }
    
    static func replace<C>(with x: C) -> (Optional<Wrapped>) -> Optional<C> {
        { items in items.replace(with: x) }
    }
    
    static func map<U>(_ transform: @escaping (Wrapped) -> U) -> (Optional<Wrapped>) -> Optional<U> {
        { items in items.map(transform) }
    }
}
