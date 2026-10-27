extension Validation: Pure {
    public typealias PureA = Value
    
    public static func pure(_ x: Value) -> Validation<Failure, Value> {
        return .success(x)
    }
}

public extension Validation {
    static func ap<O>(_ function: Validation<Failure, (Value) -> O>) -> (Self) -> Validation<Failure, O> {
        { input in
            switch (function, input) {
            case (.success(let f), .success(let x)):
                return .success(f(x))
            case (.success, .failure(let failures)):
                return .failure(failures)
            case (.failure(let failures), .success):
                return .failure(failures)
            case (.failure(let f1), .failure(let f2)):
                return .failure(f1 <> f2)
            }
        }
    }

    func apLeft<O>(_ rhs: Validation<Failure, O>) -> Self {
        Validation.ap(rhs.replace(with: identity))(self)
    }

    func apRight<O>(_ rhs: Validation<Failure, O>) -> Validation<Failure, O> {
        Validation<Failure, O>.ap(replace(with: identity))(rhs)
    }

    func liftA2<B, C>(_ other: Validation<Failure, B>, _ f: @escaping (Value, B) -> C) -> Validation<Failure, C> {
        Validation<Failure, B>.ap(map { a in { b in f(a, b) } })(other)
    }
}
