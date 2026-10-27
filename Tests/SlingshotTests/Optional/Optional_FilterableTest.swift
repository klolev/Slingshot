import Testing
@testable import Slingshot

@Suite("Optional filterable")
struct Optional_FilterableTest {
    @Suite("filter")
    struct Filter {
        @Test("returns nil when its value is nil, no matter the predicate")
        func returnsNilWhenItsValueIsNilNoMatterThePredicate() {
            #expect(Optional<Int>.none.filter(constant(false)) == nil)
            #expect(Optional<Int>.none.filter(constant(true)) == nil)
        }

        @Test("returns nil when its value is present but the predicate returns false")
        func returnsNilWhenItsValueIsPresentButThePredicateReturnsFalse() {
            #expect(Optional.some(3).filter { $0 != 3 } == nil)
        }

        @Test("returns its value when its value is present and the predicate returns true")
        func returnsItsValueWhenItsValueIsPresentAndThePredicateReturnsTrue() {
            #expect(Optional.some(3).filter { $0 == 3 } == .some(3))
        }
    }
}
