public extension Set {
    func replace<C>(with x: C) -> Set<C> {
        map(constant(x))
    }
    
    static func replace<C>(with x: C) -> (Set<Element>) -> Set<C> {
        { items in items.replace(with: x) }
    }
    
    static func map<U>(_ transform: @escaping (Element) -> U) -> (Set<Element>) -> Set<U> {
        { items in items.map(transform) }
    }
}
