@dynamicMemberLookup
public struct ArrayLens<Element> {
    private let array: [Element]
    
    init(array: [Element]) {
        self.array = array
    }
    
    public subscript<T>(dynamicMember member: KeyPath<Element, T>) -> [T] {
        array.map { $0[keyPath: member] }
    }
}

public extension Array {
    var lens: ArrayLens<Element> {
        ArrayLens(array: self)
    }
}
