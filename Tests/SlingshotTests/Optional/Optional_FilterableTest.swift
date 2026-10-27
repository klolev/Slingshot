import Quick
import Nimble
@testable import Slingshot

class Optional_FilterableTest: QuickSpec {
    override func spec() {
        describe("Optional filterable") {
            context("filter") {
                it("returns nil when its value is nil, no matter the predicate") {
                    expect(Optional<Int>.none.filter(constant(false))).to(beNil())
                    expect(Optional<Int>.none.filter(constant(true))).to(beNil())
                }

                it("returns nil when its value is present but the predicate returns false") {
                    expect(Optional.some(3).filter { $0 != 3 }).to(beNil())
                }

                it("returns its value when its value is present and the predicate returns true") {
                    expect(Optional.some(3).filter { $0 == 3 }).to(equal(.some(3)))
                }
            }
        }
    }
}
