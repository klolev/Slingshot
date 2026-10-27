import Quick
import Nimble
@testable import Slingshot

private enum LiftError: Error, Equatable {
    case first, second
}

class Result_ApplicativeTest: QuickSpec {
    override func spec() {
        describe("Result applicative") {
            context("liftA2") {
                it("combines both values if both are successes") {
                    let result = Result<Int, LiftError>.success(2).liftA2(.success(3), +)
                    expect(result).to(equal(.success(5)))
                }

                it("returns the failure if only one side fails") {
                    let lhsFails = Result<Int, LiftError>.failure(.first).liftA2(Result<Int, LiftError>.success(3), +)
                    let rhsFails = Result<Int, LiftError>.success(2).liftA2(Result<Int, LiftError>.failure(.second), +)
                    expect(lhsFails).to(equal(.failure(.first)))
                    expect(rhsFails).to(equal(.failure(.second)))
                }

                it("returns the receiver's failure if both sides fail") {
                    let result = Result<Int, LiftError>.failure(.first).liftA2(Result<Int, LiftError>.failure(.second), +)
                    expect(result).to(equal(.failure(.first)))
                }
            }
        }
    }
}
