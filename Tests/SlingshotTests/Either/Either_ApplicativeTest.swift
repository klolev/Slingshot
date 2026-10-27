import Testing
@testable import Slingshot

@Suite("Either applicative")
struct Either_ApplicativeTest {
    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both values if both are right")
        func combinesBothValuesIfBothAreRight() {
            let result = Either<String, Int>.right(2).liftA2(.right(3), +)
            #expect(result.right == 5)
        }

        @Test("returns the left if only one side is left")
        func returnsTheLeftIfOnlyOneSideIsLeft() {
            let lhsLeft = Either<String, Int>.left("first").liftA2(Either<String, Int>.right(3), +)
            let rhsLeft = Either<String, Int>.right(2).liftA2(Either<String, Int>.left("second"), +)
            #expect(lhsLeft.left == "first")
            #expect(rhsLeft.left == "second")
        }

        @Test("returns the receiver's left if both sides are left")
        func returnsTheReceiverSLeftIfBothSidesAreLeft() {
            let result = Either<String, Int>.left("first").liftA2(Either<String, Int>.left("second"), +)
            #expect(result.left == "first")
        }
    }
}
