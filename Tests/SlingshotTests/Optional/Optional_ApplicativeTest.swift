import Testing
@testable import Slingshot

@Suite("Optional applicative")
struct Optional_ApplicativeTest {
    @Suite("pure")
    struct Pure {
        @Test("lifts a value")
        func liftsAValue() {
            #expect(Optional.pure(3) == .some(3))
        }
    }

    @Suite("ap")
    struct Ap {
        @Test("returns none if the function or/and the operand is/are nil")
        func returnsNoneIfTheFunctionOrAndTheOperandIsAreNil() {
            #expect(Optional.ap(Optional<(Int) -> String>.none)(nil) == nil)
            #expect(Optional.ap({ $0 + 1 })(nil) == nil)
            #expect(Optional.ap(Optional<(Int) -> String>.none)(1) == nil)
        }

        @Test("maps its value if both the operand and the function are present")
        func mapsItsValueIfBothTheOperandAndTheFunctionArePresent() {
            #expect(Optional.ap(.some(String.init))(.some(1)) == "1")
        }
    }

    @Suite("apLeft")
    struct ApLeft {
        @Test("ignores right value and returns left value if both are present")
        func ignoresRightValueAndReturnsLeftValueIfBothArePresent() {
            #expect(.some(3).apLeft(rhs: .some(2)) == 3)
        }

        @Test("returns nil if one or both of the values are nil")
        func returnsNilIfOneOrBothOfTheValuesAreNil() {
            #expect(Optional<Int>.some(3).apLeft(rhs: Optional<String>.none) == nil)
            #expect(Optional<Int>.none.apLeft(rhs: Optional<String>.some("")) == nil)
            #expect(Optional<Int>.none.apLeft(rhs: Optional<String>.none) == nil)
        }
    }

    @Suite("apRight")
    struct ApRight {
        @Test("ignores left value and returns right value if both are present")
        func ignoresLeftValueAndReturnsRightValueIfBothArePresent() {
            #expect(.some(3).apRight(rhs: .some(2)) == 2)
        }

        @Test("returns nil if one or both of the values are nil")
        func returnsNilIfOneOrBothOfTheValuesAreNil() {
            #expect(Optional<Int>.some(3).apRight(rhs: Optional<String>.none) == nil)
            #expect(Optional<Int>.none.apRight(rhs: Optional<String>.some("")) == nil)
            #expect(Optional<Int>.none.apRight(rhs: Optional<String>.none) == nil)
        }
    }

    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both values if both are present")
        func combinesBothValuesIfBothArePresent() {
            #expect(Optional(2).liftA2(Optional(3), +) == 5)
        }

        @Test("returns nil if one or both of the values are nil")
        func returnsNilIfOneOrBothOfTheValuesAreNil() {
            #expect(Optional(2).liftA2(Optional<Int>.none, +) == nil)
            #expect(Optional<Int>.none.liftA2(Optional(3), +) == nil)
            #expect(Optional<Int>.none.liftA2(Optional<Int>.none, +) == nil)
        }
    }
}
