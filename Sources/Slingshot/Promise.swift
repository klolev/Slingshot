import Foundation

public protocol PromiseProtocol {
    associatedtype Value

    var promise: Promise<Value> { get }
}

public struct Promise<Value> {
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
