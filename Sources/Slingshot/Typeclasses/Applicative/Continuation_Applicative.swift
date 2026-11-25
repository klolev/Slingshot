extension Continuation: Pure {
    public static func pure(_ x: Argument) -> Continuation<Result, Argument> {
        .init { k in
            k(x)
        }
    }
}
