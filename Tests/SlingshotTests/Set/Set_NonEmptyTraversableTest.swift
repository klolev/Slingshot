import Testing
@testable import Slingshot

private let elements = Array(1...50)
// `first` is a member of the set, but deliberately not the one iteration starts with
private let set = Set(elements)
private let ne = Set<Int>.NonEmpty(first: set.dropFirst().first!, container: set)

@Suite("Set.NonEmpty Traversable")
struct Set_NonEmptyTraversableTest {
    @Suite("traverse (Optional)")
    struct TraverseOptional {
        @Test("visits every element exactly once")
        func visitsEveryElementExactlyOnce() {
            var visited: [Int] = []
            let result = ne.traverse { x -> Int? in visited.append(x); return x * 2 }
            #expect(visited.sorted() == elements)
            #expect(result?.erased == Set(elements.map { $0 * 2 }))
        }

        @Test("returns nil when any transform fails")
        func returnsNilWhenAnyTransformFails() {
            let result = ne.traverse { $0 == 50 ? nil : .some($0) }
            #expect(result == nil)
        }
    }

    @Suite("traverse (Validation)")
    struct TraverseValidation {
        @Test("accumulates a failure for every element")
        func accumulatesAFailureForEveryElement() {
            let result: Validation<String, Set<Int>.NonEmpty> = ne.traverse { .fail("e\($0)") }
            #expect(result.failures.sorted() == elements.map { "e\($0)" }.sorted())
        }
    }
}
