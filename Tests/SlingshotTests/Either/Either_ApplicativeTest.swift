import Quick
import Nimble
@testable import Slingshot

class Either_ApplicativeTest: QuickSpec {
    override func spec() {
        describe("Either applicative") {
            context("liftA2") {
                it("combines both values if both are right") {
                    let result = Either<String, Int>.right(2).liftA2(.right(3), +)
                    expect(result.right).to(equal(5))
                }

                it("returns the left if only one side is left") {
                    let lhsLeft = Either<String, Int>.left("first").liftA2(Either<String, Int>.right(3), +)
                    let rhsLeft = Either<String, Int>.right(2).liftA2(Either<String, Int>.left("second"), +)
                    expect(lhsLeft.left).to(equal("first"))
                    expect(rhsLeft.left).to(equal("second"))
                }

                it("returns the receiver's left if both sides are left") {
                    let result = Either<String, Int>.left("first").liftA2(Either<String, Int>.left("second"), +)
                    expect(result.left).to(equal("first"))
                }
            }
        }
    }
}
