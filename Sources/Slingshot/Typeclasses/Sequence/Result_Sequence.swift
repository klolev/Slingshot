extension Result: @retroactive Sequence {
    public struct SuccessIterator: IteratorProtocol {
        var value: Result<Success, Failure>?
        
        public mutating func next() -> Success? {
            switch value {
            case .success(let value):
                self.value = nil
                return value
            default:
                return nil
            }
        }
    }
    
    public func makeIterator() -> SuccessIterator {
        SuccessIterator(value: self)
    }
}
