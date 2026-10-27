import Quick
import Nimble
@testable import Slingshot

class Optional_FunctorTest: QuickSpec {
    override func spec() {
        describe("Optional functor") {
            context("map") {
                it("maps its value when some") {
                    expect(Optional.some(1).map { $0 + 1 }).to(equal(2))
                }

                it("maps to nil when its value is none") {
                    expect(Optional.none.map { $0 + 1 }).to(beNil())
                }
            }

            context("replace") {
                it("replaces its value when some") {
                    expect(Optional.some(1).replace(with: 2)).to(equal(2))
                }

                it("stays nil if its value is none") {
                    expect(Optional<Int>.none.replace(with: 2)).to(beNil())
                }
            }
        }
    }
}
