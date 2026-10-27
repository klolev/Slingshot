public extension Array {
    func replace<C>(with x: C) -> Array<C> {
        map(constant(x))
    }
    
    static func replace<C>(with x: C) -> (Array<Element>) -> Array<C> {
        { items in items.replace(with: x) }
    }
    
    static func map<U>(_ transform: @escaping (Element) -> U) -> (Array<Element>) -> Array<U> {
        { items in items.map(transform) }
    }
}
