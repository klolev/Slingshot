import Testing
@testable import Slingshot

private enum LiftError: Error, Equatable {
    case first, second
}

@Suite("Result applicative")
struct Result_ApplicativeTest {
    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both values if both are successes")
        func combinesBothValuesIfBothAreSuccesses() {
            let result = Result<Int, LiftError>.success(2).liftA2(.success(3), +)
            #expect(result == .success(5))
        }

        @Test("returns the failure if only one side fails")
        func returnsTheFailureIfOnlyOneSideFails() {
            let lhsFails = Result<Int, LiftError>.failure(.first).liftA2(Result<Int, LiftError>.success(3), +)
            let rhsFails = Result<Int, LiftError>.success(2).liftA2(Result<Int, LiftError>.failure(.second), +)
            #expect(lhsFails == .failure(.first))
            #expect(rhsFails == .failure(.second))
        }

        @Test("returns the receiver's failure if both sides fail")
        func returnsTheReceiverSFailureIfBothSidesFail() {
            let result = Result<Int, LiftError>.failure(.first).liftA2(Result<Int, LiftError>.failure(.second), +)
            #expect(result == .failure(.first))
        }
    }
}
