import Testing
@testable import Slingshot

@Suite("Sequence asyncStream")
struct Sequence_AsyncStreamTest {
    @Test("yields every element in order")
    func yieldsEveryElementInOrder() async {
        var values: [Int] = []
        for await value in [1, 2, 3].asyncStream {
            values.append(value)
        }
        #expect(values == [1, 2, 3])
    }

    @Test("stays lazy for infinite sequences")
    func staysLazyForInfiniteSequences() async {
        var values: [Int] = []
        for await value in (1...).asyncStream {
            values.append(value)
            if values.count == 3 { break }
        }
        #expect(values == [1, 2, 3])
    }
}
