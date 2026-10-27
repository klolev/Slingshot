import Testing
@testable import Slingshot

@Suite("Optional semigroup")
struct Optional_SemigroupTest {
    @Suite("<>")
    struct Append {
        @Test("returns nil if both operands are nil")
        func returnsNilIfBothOperandsAreNil() {
            #expect(Optional<Int>.none <> nil == nil)
        }

        @Test("returns the present operand if only one of them is present")
        func returnsThePresentOperandIfOnlyOneOfThemIsPresent() {
            #expect(Optional<Int>.some(1) <> nil == 1)
            #expect(Optional<Int>.none <> .some(1) == 1)
        }

        @Test("returns the result of the operation if both operands are present")
        func returnsTheResultOfTheOperationIfBothOperandsArePresent() {
            #expect(Optional<Int>.some(1) <> .some(2) == 3)
        }
    }
}
