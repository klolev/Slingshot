public enum TaggedDelimitations {
    public typealias Tag = Int
    
    public enum Block {
        case done(Any)
        case captured(
            tag: Tag,
            next: (Any) -> Block,
            body: ((@escaping (Any) -> Continuation<Block, Any>) -> Continuation<Block, Any>)
        )
    }
    
    public static func capture<A, R>(tag: Tag, body: @escaping (@escaping (A) -> Continuation<Block, R>) -> Continuation<Block, R>) -> Continuation<Block, A> {
        .init { k in
            .captured(
                tag: tag,
                next: { x in k(x as! A) },
                body: { k in
                    body { x in
                        k(x as Any).map { $0 as! R }
                    }.map { $0 as Any }
                }
            )
        }
    }
    
    public static func prompt<A>(tag: Tag, continuation: Continuation<Block, A>) -> Continuation<Block, A> {
        .init { k in
            deliver(tag: tag, k: k, block: continuation.run(Block.done))
        }
    }
    
    fileprivate static func deliver<A>(tag: Tag, k: @escaping (A) -> Block, block: Block) -> Block {
        switch block {
        case .done(let x):
            return k(x as! A)
        case .captured(let innerTag, let next, let body):
            if tag == innerTag {
                let resume: (Any) -> Continuation<Block, Any> = { v in
                    Continuation { k2 in deliver(tag: tag, k: k2, block: next(v)) }
                }
                return body(resume).run { x in k(x as! A) }
            } else {
                return .captured(
                    tag: innerTag,
                    next: { a in deliver(tag: tag, k: k, block: next(a)) },
                    body: body
                )
            }
        }
    }
}

public extension Continuation where Result == TaggedDelimitations.Block {
    func runPrompts() -> Either<TaggedDelimitations.Tag, Argument> {
        switch run(TaggedDelimitations.Block.done) {
        case .done(let x):
            .pure(x as! Argument)
        case .captured(tag: let tag, _, _):
            .left(tag)
        }
    }
}
