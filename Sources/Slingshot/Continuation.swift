public struct Continuation<Result, Argument> {
    public let run: (@escaping (Argument) -> Result) -> Result
    
    public init(run: @escaping (@escaping (Argument) -> Result) -> Result) {
        self.run = run
    }
}

public extension Continuation where Argument == Result {
    func evaluate() -> Result {
        run(identity(_:))
    }
    
    func reset<NewResult>() -> Continuation<NewResult, Argument> {
        .pure(evaluate())
    }
}

public extension Continuation {
    static func shift<R, A>(_ body: @escaping (@escaping (A) -> R) -> Continuation<R, R>) -> Continuation<R, A> {
        .init { k in
            body(k).evaluate()
        }
    }
}
