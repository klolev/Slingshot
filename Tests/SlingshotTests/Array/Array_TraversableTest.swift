import Foundation
import Testing
@testable import Slingshot

@Suite("Array Traversable")
struct Array_TraversableTest {
    @Suite("sequenced ([T?])")
    struct SequencedT {
        @Test("returns some empty array when the array is empty")
        func returnsSomeEmptyArrayWhenTheArrayIsEmpty() {
            #expect(Array<Int?>.zero.sequenced == [])
        }

        @Test("returns none when the array contains a none value")
        func returnsNoneWhenTheArrayContainsANoneValue() {
            #expect([0, nil].sequenced == nil)
            #expect([Optional<Int>.none].sequenced == nil)
            #expect([nil, 0].sequenced == nil)
        }

        @Test("returns some array when the array contains a no none values")
        func returnsSomeArrayWhenTheArrayContainsANoNoneValues() {
            #expect([Optional.some(0), 1].sequenced == [0, 1])
            #expect([Optional.some(0)].sequenced == [0])
            #expect([Optional.some(Optional.some(0))].sequenced == [Optional.some(0)])
        }
    }

    @Suite("traverse (Optional)")
    struct TraverseOptional {
        @Test("returns some when all transforms succeed")
        func returnsSomeWhenAllTransformsSucceed() {
            let result = [1, 2, 3].traverse { $0 > 0 ? .some($0 * 2) : nil }
            #expect(result == [2, 4, 6])
        }

        @Test("returns nil when any transform fails")
        func returnsNilWhenAnyTransformFails() {
            let result = [1, -1, 3].traverse { $0 > 0 ? .some($0 * 2) : nil }
            #expect(result == nil)
        }

        @Test("returns some empty array for empty input")
        func returnsSomeEmptyArrayForEmptyInput() {
            let result = [Int]().traverse { Optional.some($0) }
            #expect(result == [])
        }
    }

    @Suite("traverse (Result)")
    struct TraverseResult {
        @Test("returns success when all transforms succeed")
        func returnsSuccessWhenAllTransformsSucceed() {
            let result: Result<[Int], TestError> = [1, 2, 3].traverse { .success($0 * 2) }
            #expect(result == .success([2, 4, 6]))
        }

        @Test("returns failure when any transform fails")
        func returnsFailureWhenAnyTransformFails() {
            let result: Result<[Int], TestError> = [1, 2, 3].traverse { $0 == 2 ? .failure(.bad) : .success($0) }
            #expect(result == .failure(.bad))
        }

        @Test("returns success empty for empty input")
        func returnsSuccessEmptyForEmptyInput() {
            let result: Result<[Int], TestError> = [Int]().traverse { .success($0) }
            #expect(result == .success([]))
        }
    }

    @Suite("traverse (Validation)")
    struct TraverseValidation {
        @Test("returns success when all transforms succeed")
        func returnsSuccessWhenAllTransformsSucceed() {
            let result: Validation<String, [Int]> = [1, 2, 3].traverse { .success($0 * 2) }
            #expect(result.value == [2, 4, 6])
        }

        @Test("accumulates all failures")
        func accumulatesAllFailures() {
            let result: Validation<String, [Int]> = [1, 2, 3].traverse {
                $0 % 2 == 0 ? .fail("even: \($0)") : .success($0)
            }
            #expect(result.failures == ["even: 2"])
        }

        @Test("accumulates multiple failures")
        func accumulatesMultipleFailures() {
            let result: Validation<String, [Int]> = [2, 4, 6].traverse { .fail("bad: \($0)") }
            #expect(result.failures == ["bad: 2", "bad: 4", "bad: 6"])
        }
    }

    @Suite("traverse (Either)")
    struct TraverseEither {
        @Test("returns right when all transforms succeed")
        func returnsRightWhenAllTransformsSucceed() {
            let result: Either<String, [Int]> = [1, 2, 3].traverse { .right($0 * 2) }
            #expect(result.right == [2, 4, 6])
        }

        @Test("returns left on first failure")
        func returnsLeftOnFirstFailure() {
            let result: Either<String, [Int]> = [1, 2, 3].traverse {
                $0 == 2 ? .left("fail") : .right($0)
            }
            #expect(result.left == "fail")
        }
    }

    @Suite("sequenced ([Result])")
    struct SequencedResult {
        @Test("returns success when all elements are success")
        func returnsSuccessWhenAllElementsAreSuccess() {
            let input: [Result<Int, TestError>] = [.success(1), .success(2), .success(3)]
            #expect(input.sequenced == .success([1, 2, 3]))
        }

        @Test("returns failure when any element is failure")
        func returnsFailureWhenAnyElementIsFailure() {
            let input: [Result<Int, TestError>] = [.success(1), .failure(.bad), .success(3)]
            #expect(input.sequenced == .failure(.bad))
        }
    }

    @Suite("sequenced ([Either])")
    struct SequencedEither {
        @Test("returns right when all elements are right")
        func returnsRightWhenAllElementsAreRight() {
            let input: [Either<String, Int>] = [.right(1), .right(2)]
            #expect(input.sequenced.right == [1, 2])
        }

        @Test("returns left on first left")
        func returnsLeftOnFirstLeft() {
            let input: [Either<String, Int>] = [.right(1), .left("oops")]
            #expect(input.sequenced.left == "oops")
        }
    }

    @Suite("traverse (IO)")
    struct TraverseIO {
        @Test("resolves to the transformed values in order")
        func resolvesToTheTransformedValuesInOrder() async {
            let result = await [1, 2, 3].traverse { IO.pure($0 * 2) }.value
            #expect(result == [2, 4, 6])
        }

        @Test("handles large inputs without overflowing the stack")
        func handlesLargeInputsWithoutOverflowingTheStack() async {
            let input = Array(0..<100_000)
            let result = await input.traverse { IO.pure($0) }.value
            #expect(result == input)
        }
    }
}

enum TestError: Error, Equatable {
    case bad
}
