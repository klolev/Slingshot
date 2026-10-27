import Testing
@testable import Slingshot

@Suite("Optional Traversable")
struct Optional_TraversableTest {
    @Suite("traverse (Optional)")
    struct TraverseOptional {
        @Test("returns nested some when value present and transform succeeds")
        func returnsNestedSomeWhenValuePresentAndTransformSucceeds() {
            let result: Optional<Int>? = Optional.some(3).traverse { .some($0 * 2) }
            #expect(result == .some(.some(6)))
        }

        @Test("returns some none when value present but transform returns nil")
        func returnsSomeNoneWhenValuePresentButTransformReturnsNil() {
            let result = Optional.some(3).traverse { _ -> Int? in nil }
            #expect(result == nil)
        }

        @Test("returns some none when value is nil")
        func returnsSomeNoneWhenValueIsNil() {
            let result: Optional<Int>? = Optional<Int>.none.traverse { .some($0 * 2) }
            #expect(result == .some(.none))
        }
    }

    @Suite("traverse (Result)")
    struct TraverseResult {
        @Test("returns success some when value present and transform succeeds")
        func returnsSuccessSomeWhenValuePresentAndTransformSucceeds() {
            let result: Result<Int?, TestError> = Optional.some(3).traverse { .success($0 * 2) }
            #expect(result == .success(.some(6)))
        }

        @Test("returns failure when value present and transform fails")
        func returnsFailureWhenValuePresentAndTransformFails() {
            let result: Result<Int?, TestError> = Optional.some(3).traverse { _ in Result<Int, TestError>.failure(.bad) }
            #expect(result == .failure(.bad))
        }

        @Test("returns success nil when value is nil")
        func returnsSuccessNilWhenValueIsNil() {
            let result: Result<Int?, TestError> = Optional<Int>.none.traverse { .success($0) }
            #expect(result == .success(nil))
        }
    }

    @Suite("traverse (Either)")
    struct TraverseEither {
        @Test("returns right some when value present and transform returns right")
        func returnsRightSomeWhenValuePresentAndTransformReturnsRight() {
            let result: Either<String, Int?> = Optional.some(5).traverse { .right($0 + 1) }
            #expect(result.right == .some(6))
        }

        @Test("returns left when value present and transform returns left")
        func returnsLeftWhenValuePresentAndTransformReturnsLeft() {
            let result: Either<String, Int?> = Optional.some(5).traverse { _ in Either<String, Int>.left("nope") }
            #expect(result.left == "nope")
        }

        @Test("returns right nil when value is nil")
        func returnsRightNilWhenValueIsNil() {
            let result: Either<String, Int?> = Optional<Int>.none.traverse { .right($0) }
            #expect(result.right ?? .some(99) == nil)
        }
    }

    @Suite("sequenced (Optional<Result>)")
    struct SequencedOptionalResult {
        @Test("returns success some when some success")
        func returnsSuccessSomeWhenSomeSuccess() {
            let input: Result<Int, TestError>? = .some(.success(42))
            #expect(input.sequenced == .success(.some(42)))
        }

        @Test("returns failure when some failure")
        func returnsFailureWhenSomeFailure() {
            let input: Result<Int, TestError>? = .some(.failure(.bad))
            #expect(input.sequenced == .failure(.bad))
        }

        @Test("returns success nil when nil")
        func returnsSuccessNilWhenNil() {
            let input: Result<Int, TestError>? = nil
            #expect(input.sequenced == .success(nil))
        }
    }

    @Suite("sequenced (Optional<Either>)")
    struct SequencedOptionalEither {
        @Test("returns right some when some right")
        func returnsRightSomeWhenSomeRight() {
            let input: Either<String, Int>? = .some(.right(10))
            #expect(input.sequenced.right == .some(10))
        }

        @Test("returns left when some left")
        func returnsLeftWhenSomeLeft() {
            let input: Either<String, Int>? = .some(.left("err"))
            #expect(input.sequenced.left == "err")
        }

        @Test("returns right nil when nil")
        func returnsRightNilWhenNil() {
            let input: Either<String, Int>? = nil
            #expect(input.sequenced.right ?? .some(99) == nil)
        }
    }
}
