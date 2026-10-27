import Testing
@testable import Slingshot

@Suite("Validation applicative")
struct Validation_ApplicativeTest {
    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both values if both are successes")
        func combinesBothValuesIfBothAreSuccesses() {
            let result = Validation<String, Int>.success(2).liftA2(.success(3), +)
            #expect(result.value == 5)
        }

        @Test("returns the failures if only one side fails")
        func returnsTheFailuresIfOnlyOneSideFails() {
            let lhsFails = Validation<String, Int>.fail("first").liftA2(Validation<String, Int>.success(3), +)
            let rhsFails = Validation<String, Int>.success(2).liftA2(Validation<String, Int>.fail("second"), +)
            #expect(lhsFails.failures == ["first"])
            #expect(rhsFails.failures == ["second"])
        }

        @Test("accumulates the failures of both sides, receiver's first")
        func accumulatesTheFailuresOfBothSidesReceiverSFirst() {
            let result = Validation<String, Int>.fail("first").liftA2(Validation<String, Int>.fail("second"), +)
            #expect(result.failures == ["first", "second"])
        }
    }
}
