@resultBuilder
public struct SequenceBuilder<Container> where Container: Sequence & Monoid & Pure, Container.PureA == Container.Element {
    public static func buildPartialBlock<V>(first content: V) -> Container where V: Sequence, V.Element == Container.Element {
        Container.fromSequence(content)
    }
    
    public static func buildPartialBlock<V>(accumulated: Container, next: V) -> Container where V: Sequence, V.Element == Container.Element {
        accumulated <> Container.fromSequence(next)
    }
    
    public static func buildOptional<V>(_ component: V?) -> Container where V: Sequence, V.Element == Container.Element {
        if let component {
            Container.fromSequence(component)
        } else {
            Container.zero
        }
    }
    
    public static func buildEither<V>(first component: V) -> Container where V: Sequence, V.Element == Container.Element {
        Container.fromSequence(component)
    }
    
    public static func buildEither<V>(second component: V) -> Container where V: Sequence, V.Element == Container.Element {
        Container.fromSequence(component)
    }
}
