import Testing
@testable import Slingshot

@Suite("Concurrently Traversable")
struct Concurrently_TraversableTest {
    @Suite("traverse (Array)")
    struct TraverseArray {
        @Test("keeps the input order even when later elements finish first")
        func keepsTheInputOrderEvenWhenLaterElementsFinishFirst() async {
            let tracker = InFlight()
            let result = await [1, 2, 3].traverse { x in
                tracked(x * 2, tracker, delayNanoseconds: UInt64(4 - x) * 20_000_000)
            }.value
            #expect(result == [2, 4, 6])
        }

        @Test("runs every element at the same time")
        func runsEveryElementAtTheSameTime() async {
            let tracker = InFlight()
            _ = await Array(0..<5).traverse { tracked($0, tracker) }.value
            #expect(await tracker.peak == 5)
        }

        @Test("returns an empty array for an empty input")
        func returnsAnEmptyArrayForAnEmptyInput() async {
            #expect(await [Int]().traverse { Concurrently.pure($0) }.value == [])
        }

        @Test("sequenced resolves every element")
        func sequencedResolvesEveryElement() async {
            #expect(await [Concurrently.pure(1), .pure(2)].sequenced.value == [1, 2])
        }
    }

    @Suite("traverse (NonEmpty)")
    struct TraverseNonEmpty {
        @Test("keeps the first element and the order")
        func keepsTheFirstElementAndTheOrder() async {
            let result = await [Int].NonEmpty(first: 1, 2, 3).traverse { Concurrently.pure($0 * 10) }.value
            #expect(result.first == 10)
            #expect(result.erased == [10, 20, 30])
        }
    }

    @Suite("traverse (Set)")
    struct TraverseSet {
        @Test("resolves to the transformed set")
        func resolvesToTheTransformedSet() async {
            #expect(await Set([1, 2, 3]).traverse { Concurrently.pure($0 % 2) }.value == [0, 1])
        }
    }

    @Suite("traverse (String)")
    struct TraverseString {
        @Test("rebuilds the string in order")
        func rebuildsTheStringInOrder() async {
            let result = await "abc".traverse { c in Concurrently.pure(Character(c.uppercased())) }.value
            #expect(result == "ABC")
        }
    }

    @Suite("Optional")
    struct OptionalTraversal {
        @Test("traverse resolves some and none")
        func traverseResolvesSomeAndNone() async {
            #expect(await Optional(2).traverse { Concurrently.pure($0 + 1) }.value == 3)
            #expect(await Optional<Int>.none.traverse { Concurrently.pure($0 + 1) }.value == nil)
        }

        @Test("sequenced resolves the wrapped computation")
        func sequencedResolvesTheWrappedComputation() async {
            #expect(await Optional(Concurrently.pure(4)).sequenced.value == 4)
        }
    }

    @Suite("Result")
    struct ResultTraversal {
        @Test("sequenced resolves a success and keeps a failure")
        func sequencedResolvesASuccessAndKeepsAFailure() async {
            let success: Result<Concurrently<Result<Int, TestError>>, TestError> = .success(.pure(.success(1)))
            let failure: Result<Concurrently<Result<Int, TestError>>, TestError> = .failure(.bad)
            #expect(await success.sequenced.value == .success(1))
            #expect(await failure.sequenced.value == .failure(.bad))
        }
    }
}
