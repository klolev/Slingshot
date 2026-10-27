import Quick
import Nimble
@testable import Slingshot

class Validation_ApplicativeTest: QuickSpec {
    override func spec() {
        describe("Validation applicative") {
            context("liftA2") {
                it("combines both values if both are successes") {
                    let result = Validation<String, Int>.success(2).liftA2(.success(3), +)
                    expect(result.value).to(equal(5))
                }

                it("returns the failures if only one side fails") {
                    let lhsFails = Validation<String, Int>.fail("first").liftA2(Validation<String, Int>.success(3), +)
                    let rhsFails = Validation<String, Int>.success(2).liftA2(Validation<String, Int>.fail("second"), +)
                    expect(lhsFails.failures).to(equal(["first"]))
                    expect(rhsFails.failures).to(equal(["second"]))
                }

                it("accumulates the failures of both sides, receiver's first") {
                    let result = Validation<String, Int>.fail("first").liftA2(Validation<String, Int>.fail("second"), +)
                    expect(result.failures).to(equal(["first", "second"]))
                }
            }
        }
    }
}
