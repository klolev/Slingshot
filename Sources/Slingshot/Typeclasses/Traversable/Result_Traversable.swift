public extension Result where Element: OptionalProtocol, Element.Wrapped: ResultProtocol, Element.Wrapped.Failure == Failure {
    var sequenced: Result<Element.Wrapped.Success, Element.Wrapped.Failure>? {
        switch self {
        case .success(let success):
            success.value.map(\.result)
        case .failure(let failure):
            .pure(.failure(failure))
        }
    }
}

public extension Result where Element: PromiseProtocol, Element.Value: ResultProtocol, Element.Value.Failure == Failure {
    var sequenced: Promise<Result<Element.Value.Success, Element.Value.Failure>> {
        switch self {
        case .success(let success):
            success.promise.map(\.result)
        case .failure(let failure):
            .pure(.failure(failure))
        }
    }
}
