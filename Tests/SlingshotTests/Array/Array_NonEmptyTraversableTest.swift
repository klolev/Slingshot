import Testing
@testable import Slingshot

@Suite("Array.NonEmpty Traversable")
struct Array_NonEmptyTraversableTest {
    @Suite("traverse (Optional)")
    struct TraverseOptional {
        @Test("returns some nonempty when all transforms succeed")
        func returnsSomeNonemptyWhenAllTransformsSucceed() {
            let ne = [Int].NonEmpty(first: 1, 2, 3)
            let result = ne.traverse { .some($0 * 2) }
            #expect(result?.first == 2)
            #expect(result?.erased == [2, 4, 6])
        }

        @Test("returns nil when any transform fails")
        func returnsNilWhenAnyTransformFails() {
            let ne = [Int].NonEmpty(first: 1, 2, 3)
            let result = ne.traverse { $0 == 2 ? nil : .some($0) }
            #expect(result == nil)
        }
    }

    @Suite("traverse (Result)")
    struct TraverseResult {
        @Test("returns success nonempty when all succeed")
        func returnsSuccessNonemptyWhenAllSucceed() throws {
            let ne = [Int].NonEmpty(first: 10, 20)
            let result: Result<[Int].NonEmpty, TestError> = ne.traverse { .success($0 + 1) }
            #expect(try result.get().erased == [11, 21])
        }

        @Test("returns failure when any fails")
        func returnsFailureWhenAnyFails() {
            let ne = [Int].NonEmpty(first: 1, 2)
            let result: Result<[Int].NonEmpty, TestError> = ne.traverse { _ in .failure(.bad) }
            #expect(result == .failure(.bad))
        }
    }

    @Suite("traverse (Either)")
    struct TraverseEither {
        @Test("returns right nonempty when all succeed")
        func returnsRightNonemptyWhenAllSucceed() {
            let ne = [Int].NonEmpty(first: 5, 6)
            let result: Either<String, [Int].NonEmpty> = ne.traverse { .right($0 * 3) }
            #expect(result.right?.erased == [15, 18])
        }

        @Test("returns left on failure")
        func returnsLeftOnFailure() {
            let ne = [Int].NonEmpty(first: 1)
            let result: Either<String, [Int].NonEmpty> = ne.traverse { _ in .left("no") }
            #expect(result.left == "no")
        }
    }

    @Suite("traverse (Validation)")
    struct TraverseValidation {
        @Test("returns success when all succeed")
        func returnsSuccessWhenAllSucceed() {
            let ne = [Int].NonEmpty(first: 1, 2)
            let result: Validation<String, [Int].NonEmpty> = ne.traverse { .success($0 * 10) }
            #expect(result.value?.erased == [10, 20])
        }

        @Test("accumulates failures")
        func accumulatesFailures() {
            let ne = [Int].NonEmpty(first: 1, 2, 3)
            let result: Validation<String, [Int].NonEmpty> = ne.traverse { .fail("e\($0)") }
            #expect(result.failures == ["e1", "e2", "e3"])
        }
    }

    @Suite("traverse visits each element exactly once")
    struct TraverseVisitsEachElementExactlyOnce {
        @Test("follows the container when it does not start with first")
        func followsTheContainerWhenItDoesNotStartWithFirst() {
            let ne = [Int].NonEmpty(first: 0, container: [5, 6])
            var visited: [Int] = []
            let result = ne.traverse { x -> Int? in visited.append(x); return x }
            #expect(visited == [5, 6])
            #expect(result?.erased == [5, 6])
        }
    }
}
