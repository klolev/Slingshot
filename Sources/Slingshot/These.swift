public enum These<This, That> {
    case this(This)
    case that(That)
    case both(This, That)
}

extension These: Equatable where This: Equatable, That: Equatable {}
extension These: Hashable where This: Hashable, That: Hashable {}
extension These: Decodable where This: Decodable, That: Decodable {}
extension These: Encodable where This: Encodable, That: Encodable {}
extension These: Sendable where This: Sendable, That: Sendable {}
