import Quick
import Nimble
@testable import Slingshot

class Optional_SemigroupTest: QuickSpec {
    override func spec() {
        describe("Optional semigroup") {
            context("<>") {
                it("returns nil if both operands are nil") {
                    expect(Optional<Int>.none <> nil).to(beNil())
                }

                it("returns the present operand if only one of them is present") {
                    expect(Optional<Int>.some(1) <> nil).to(equal(1))
                    expect(Optional<Int>.none <> .some(1)).to(equal(1))
                }

                it("returns the result of the operation if both operands are present") {
                    expect(Optional<Int>.some(1) <> .some(2)).to(equal(3))
                }
            }
        }
    }
}
