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

public extension Result where Element: IOProtocol, Element.Value: ResultProtocol, Element.Value.Failure == Failure {
    var sequenced: IO<Result<Element.Value.Success, Element.Value.Failure>> {
        switch self {
        case .success(let success):
            success.io.map(\.result)
        case .failure(let failure):
            .pure(.failure(failure))
        }
    }
}

public extension Result where Element: ConcurrentlyProtocol, Element.Value: ResultProtocol, Element.Value.Success: Sendable, Element.Value.Failure == Failure {
    var sequenced: Concurrently<Result<Element.Value.Success, Element.Value.Failure>> {
        switch self {
        case .success(let success):
            success.concurrently.map(\.result)
        case .failure(let failure):
            .pure(.failure(failure))
        }
    }
}
