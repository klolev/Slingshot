import Testing
@testable import Slingshot

@Suite("Concurrently short-circuiting traversals")
struct Concurrently_ShortCircuitingTest {
    @Suite("traverse (Array, Either)")
    struct TraverseEither {
        @Test("resolves to every right value in order")
        func resolvesToEveryRightValueInOrder() async {
            let result: Either<String, [Int]> = await [1, 2, 3].traverse { x in
                Concurrently.pure(Either<String, Int>.right(x * 2))
            }.value
            #expect(result.right == [2, 4, 6])
        }

        @Test("returns the first left in input order, not the first to finish")
        func returnsTheFirstLeftInInputOrderNotTheFirstToFinish() async {
            let log = CancellationLog()
            let result = await [0, 1].traverse { index in
                sleeper(index, Either<String, Int>.left("left \(index)"), nanoseconds: index == 0 ? 50_000_000 : 0, log)
            }.value
            #expect(result.left == "left 0")
        }

        @Test("cancels the elements after a failure")
        func cancelsTheElementsAfterAFailure() async {
            let log = CancellationLog()
            let result = await [0, 1].traverse { index in
                index == 0
                    ? Concurrently.pure(Either<String, Int>.left("bad"))
                    : sleeper(index, .right(index), nanoseconds: 10_000_000_000, log)
            }.value
            #expect(result.left == "bad")
            #expect(await log.cancelled == [1])
        }

        @Test("lets the elements before a failure finish")
        func letsTheElementsBeforeAFailureFinish() async {
            let log = CancellationLog()
            let result = await [0, 1].traverse { index in
                index == 0
                    ? sleeper(index, Either<String, Int>.right(index), nanoseconds: 50_000_000, log)
                    : Concurrently.pure(.left("bad"))
            }.value
            #expect(result.left == "bad")
            #expect(await log.finished == [0])
            #expect(await log.cancelled == [])
        }
    }

    @Suite("traverse (Array, Result)")
    struct TraverseResult {
        @Test("returns the first failure in input order")
        func returnsTheFirstFailureInInputOrder() async {
            let result: Result<[Int], TestError> = await [1, 2, 3].traverse { x in
                Concurrently.pure(x == 2 ? .failure(.bad) : .success(x))
            }.value
            #expect(result == .failure(.bad))
        }

        @Test("catching captures typed errors and get rethrows them")
        func catchingCapturesTypedErrorsAndGetRethrowsThem() async {
            let traversal = [1, 2, 3].traverse { x in
                Concurrently(catching: { () async throws(TestError) -> Int in
                    if x == 2 { throw .bad }
                    return x
                })
            }
            await #expect(throws: TestError.bad) {
                try await traversal.value.get()
            }
        }

        @Test("catching untyped throwing work resolves to every success")
        func catchingUntypedThrowingWorkResolvesToEverySuccess() async throws {
            let traversal: Concurrently<Result<[Int], any Error>> = [1, 2, 3].traverse { x in
                Concurrently(catching: { try timesTen(x) })
            }
            #expect(try await traversal.value.get() == [10, 20, 30])
        }
    }

    @Suite("traverse (Array, Optional)")
    struct TraverseOptional {
        @Test("returns nil when any element is nil and cancels the rest")
        func returnsNilWhenAnyElementIsNilAndCancelsTheRest() async {
            let log = CancellationLog()
            let result = await [0, 1].traverse { index in
                index == 0 ? Concurrently.pure(nil) : sleeper(index, Optional(index), nanoseconds: 10_000_000_000, log)
            }.value
            #expect(result == nil)
            #expect(await log.cancelled == [1])
        }

        @Test("returns every value when none are nil")
        func returnsEveryValueWhenNoneAreNil() async {
            #expect(await [1, 2].traverse { Concurrently.pure(Optional($0)) }.value == [1, 2])
        }
    }

    @Suite("other containers")
    struct OtherContainers {
        @Test("NonEmpty keeps its shape")
        func nonEmptyKeepsItsShape() async {
            let result = await [Int].NonEmpty(first: 1, 2).traverse { Concurrently.pure(Either<String, Int>.right($0)) }.value
            #expect(result.right?.erased == [1, 2])
        }

        @Test("String rebuilds or fails")
        func stringRebuildsOrFails() async {
            #expect(await "ab".traverse { c in Concurrently.pure(Optional(c)) }.value == "ab")
            #expect(await "a1".traverse { c in Concurrently.pure(c.isLetter ? c : nil) }.value == nil)
        }

        @Test("Optional wraps the inner applicative")
        func optionalWrapsTheInnerApplicative() async {
            #expect(await Optional(1).traverse { Concurrently.pure(Either<String, Int>.right($0)) }.value.right == 1)
            #expect(await Optional<Int>.none.traverse { Concurrently.pure(Either<String, Int>.right($0)) }.value.right == .some(nil))
        }
    }
}

/// Throws untyped errors, so `catching` infers `any Error`.
func timesTen(_ x: Int) throws -> Int { x * 10 }

/// Records which sleepers were cancelled and which ran to the end.
actor CancellationLog {
    private(set) var cancelled: [Int] = []
    private(set) var finished: [Int] = []

    func record(_ index: Int, wasCancelled: Bool) {
        if wasCancelled {
            cancelled.append(index)
        } else {
            finished.append(index)
        }
    }
}

/// A computation that resolves to `result` after sleeping, logging whether it was cancelled first.
func sleeper<T: Sendable>(_ index: Int, _ result: T, nanoseconds: UInt64, _ log: CancellationLog) -> Concurrently<T> {
    Concurrently {
        try? await Task.sleep(nanoseconds: nanoseconds)
        await log.record(index, wasCancelled: Task.isCancelled)
        return result
    }
}
