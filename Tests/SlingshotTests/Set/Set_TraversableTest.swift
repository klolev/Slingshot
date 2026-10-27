import Testing
@testable import Slingshot

@Suite("Set Traversable")
struct Set_TraversableTest {
    @Suite("traverse (Optional)")
    struct TraverseOptional {
        @Test("returns some when all transforms succeed")
        func returnsSomeWhenAllTransformsSucceed() {
            let result = Set([1, 2, 3]).traverse { $0 > 0 ? .some($0 * 2) : nil }
            #expect(result == Set([2, 4, 6]))
        }

        @Test("returns nil when any transform fails")
        func returnsNilWhenAnyTransformFails() {
            let result = Set([1, -1, 3]).traverse { $0 > 0 ? .some($0 * 2) : nil }
            #expect(result == nil)
        }

        @Test("returns some empty set for empty input")
        func returnsSomeEmptySetForEmptyInput() {
            let result = Set<Int>().traverse { Optional.some($0) }
            #expect(result == Set())
        }
    }

    @Suite("traverse (Result)")
    struct TraverseResult {
        @Test("returns success when all transforms succeed")
        func returnsSuccessWhenAllTransformsSucceed() {
            let result: Result<Set<Int>, TestError> = Set([1, 2, 3]).traverse { .success($0 * 2) }
            #expect(result == .success(Set([2, 4, 6])))
        }

        @Test("returns failure when any transform fails")
        func returnsFailureWhenAnyTransformFails() {
            let result: Result<Set<Int>, TestError> = Set([1, 2, 3]).traverse { $0 == 2 ? .failure(.bad) : .success($0) }
            #expect(result == .failure(.bad))
        }
    }

    @Suite("traverse (Either)")
    struct TraverseEither {
        @Test("returns right when all transforms succeed")
        func returnsRightWhenAllTransformsSucceed() {
            let result: Either<String, Set<Int>> = Set([1, 2, 3]).traverse { .right($0 * 2) }
            #expect(result.right == Set([2, 4, 6]))
        }

        @Test("returns left on first failure")
        func returnsLeftOnFirstFailure() {
            let result: Either<String, Set<Int>> = Set([1]).traverse { _ in Either<String, Int>.left("fail") }
            #expect(result.left == "fail")
        }
    }

    @Suite("traverse (Validation)")
    struct TraverseValidation {
        @Test("returns success when all succeed")
        func returnsSuccessWhenAllSucceed() {
            let result: Validation<String, Set<Int>> = Set([1, 3]).traverse { .success($0) }
            #expect(result.value == Set([1, 3]))
        }

        @Test("accumulates failures")
        func accumulatesFailures() {
            let result: Validation<String, Set<Int>> = Set([1]).traverse { .fail("err\($0)") }
            #expect(result.failures == ["err1"])
        }
    }

    @Suite("sequenced (Set<Optional>)")
    struct SequencedSetOptional {
        @Test("returns some set when all elements are some")
        func returnsSomeSetWhenAllElementsAreSome() {
            let input: Set<Int?> = [.some(1), .some(2), .some(3)]
            #expect(input.sequenced == Set([1, 2, 3]))
        }

        @Test("returns nil when any element is nil")
        func returnsNilWhenAnyElementIsNil() {
            let input: Set<Int?> = [.some(1), .none]
            #expect(input.sequenced == nil)
        }

        @Test("returns some empty set for empty input")
        func returnsSomeEmptySetForEmptyInput() {
            let input: Set<Int?> = []
            #expect(input.sequenced == Set())
        }
    }
}
