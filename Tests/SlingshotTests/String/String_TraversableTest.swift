import Testing
@testable import Slingshot

private func upper(_ c: Character) -> Character { Character(c.uppercased()) }

@Suite("String Traversable")
struct String_TraversableTest {
    @Suite("traverse (Optional)")
    struct TraverseOptional {
        @Test("returns the transformed string when all transforms succeed")
        func returnsTheTransformedStringWhenAllTransformsSucceed() {
            #expect("abc".traverse { $0.isLetter ? upper($0) : nil } == "ABC")
        }

        @Test("returns nil when any transform fails")
        func returnsNilWhenAnyTransformFails() {
            #expect("a1c".traverse { $0.isLetter ? upper($0) : nil } == nil)
        }

        @Test("returns some empty string for empty input")
        func returnsSomeEmptyStringForEmptyInput() {
            #expect("".traverse { Optional.some($0) } == "")
        }
    }

    @Suite("traverse (Result)")
    struct TraverseResult {
        @Test("returns the first failure")
        func returnsTheFirstFailure() {
            let result: Result<String, TestError> = "a1c2".traverse { $0.isLetter ? .success($0) : .failure(.bad) }
            #expect(result == .failure(.bad))
        }
    }

    @Suite("traverse (Validation)")
    struct TraverseValidation {
        @Test("accumulates a failure for every rejected character")
        func accumulatesAFailureForEveryRejectedCharacter() {
            let result: Validation<Character, String> = "a1c2".traverse { $0.isLetter ? .success(upper($0)) : .fail($0) }
            #expect(result.failures == ["1", "2"])
        }
    }

    @Suite("traverse (Either)")
    struct TraverseEither {
        @Test("returns right with the transformed string")
        func returnsRightWithTheTransformedString() {
            let result: Either<String, String> = "abc".traverse { .right(upper($0)) }
            #expect(result.right == "ABC")
        }
    }

    @Suite("traverse (IO)")
    struct TraverseIO {
        @Test("resolves to the transformed string")
        func resolvesToTheTransformedString() async {
            let result = await "abc".traverse { IO.pure(upper($0)) }.value
            #expect(result == "ABC")
        }
    }

    @Suite("Substring")
    struct SubstringTraversal {
        @Test("traverses into a Substring")
        func traversesIntoASubstring() {
            let result: Substring? = "xabcx".dropFirst().dropLast().traverse { upper($0) }
            #expect(result == "ABC")
        }
    }

    @Suite("Array keeping its element type")
    struct ArrayKeepingItsElementType {
        @Test("still resolves to an array")
        func stillResolvesToAnArray() {
            let result: [Int]? = [1, 2, 3].traverse { .some($0 * 2) }
            #expect(result == [2, 4, 6])
            #expect([1, 2, 3].traverse { Optional.some($0 * 2) } == [2, 4, 6])
        }
    }
}
