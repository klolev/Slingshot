import Foundation

public protocol IOProtocol {
    associatedtype Value

    var io: IO<Value> { get }
}

public struct IO<Value> {
    let _f: () async -> Value
    
    public init(_ f: @escaping () async -> Value) {
        self._f = f
    }
    
    public var value: Value {
        get async {
            await _f()
        }
    }
}

extension IO: IOProtocol {
    public var io: IO<Value> { self }
}
