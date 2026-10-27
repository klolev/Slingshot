extension Optional: Pure {
    public typealias PureA = Wrapped
    
    public static func pure(_ x: Wrapped) -> Wrapped? {
        .some(x)
    }
}

public extension Optional {
    static func ap<O>(_ function: ((Wrapped) -> O)?) -> (Self) -> O? {
        { input in
            switch (function, input) {
            case (.some(let f), .some(let x)):
                return f(x)
            default:
                return .zero
            }
        }
    }

    func apLeft<O>(rhs: O?) -> Self {
        switch (self, rhs) {
        case (.some(let x), .some):
            return x
        default:
            return .zero
        }
    }

    func apRight<O>(rhs: O?) -> O? {
        switch (self, rhs) {
        case (.some, .some(let x)):
            return x
        default:
            return .zero
        }
    }

    func liftA2<B, C>(_ other: B?, _ f: @escaping (Wrapped, B) -> C) -> C? {
        Optional<B>.ap(map { a in { b in f(a, b) } })(other)
    }
}
