public extension These {
    func bimap<C, D>(onLeft: @escaping (This) throws -> C, onRight: @escaping (That) throws -> D) rethrows -> These<C, D> {
        switch self {
        case .this(let this):
            .this(try onLeft(this))
        case .that(let that):
            .that(try onRight(that))
        case .both(let this, let that):
            try .both(onLeft(this), onRight(that))
        }
    }
    
    static func bimap<C, D>(onLeft: @escaping (This) throws -> C, onRight: @escaping (That) throws -> D) -> (These<This, That>) throws -> These<C, D> {
        { x in try x.bimap(onLeft: onLeft, onRight: onRight) }
    }
    
    static func bimap<C, D>(onLeft: @escaping (This) -> C, onRight: @escaping (That) -> D) -> (These<This, That>) -> These<C, D> {
        { x in x.bimap(onLeft: onLeft, onRight: onRight) }
    }
}
