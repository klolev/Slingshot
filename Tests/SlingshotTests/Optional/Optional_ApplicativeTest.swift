import Quick
import Nimble
@testable import Slingshot

class Optional_ApplicativeTest: QuickSpec {
    override func spec() {
        describe("Optional applicative") {
            context("pure") {
                it("lifts a value") {
                    expect(Optional.pure(3)).to(equal(.some(3)))
                }
            }

            context("ap") {
                it("returns none if the function or/and the operand is/are nil") {
                    expect(Optional.ap(Optional<(Int) -> String>.none)(nil)).to(beNil())
                    expect(Optional.ap({ $0 + 1 })(nil)).to(beNil())
                    expect(Optional.ap(Optional<(Int) -> String>.none)(1)).to(beNil())
                }

                it("maps its value if both the operand and the function are present") {
                    expect(Optional.ap(.some(String.init))(.some(1))).to(equal("1"))
                }
            }

            context("apLeft") {
                it("ignores right value and returns left value if both are present") {
                    expect(.some(3).apLeft(rhs: .some(2))).to(equal(3))
                }

                it("returns nil if one or both of the values are nil") {
                    expect(Optional<Int>.some(3).apLeft(rhs: Optional<String>.none)).to(beNil())
                    expect(Optional<Int>.none.apLeft(rhs: Optional<String>.some(""))).to(beNil())
                    expect(Optional<Int>.none.apLeft(rhs: Optional<String>.none)).to(beNil())
                }
            }

            context("apRight") {
                it("ignores left value and returns right value if both are present") {
                    expect(.some(3).apRight(rhs: .some(2))).to(equal(2))
                }

                it("returns nil if one or both of the values are nil") {
                    expect(Optional<Int>.some(3).apRight(rhs: Optional<String>.none)).to(beNil())
                    expect(Optional<Int>.none.apRight(rhs: Optional<String>.some(""))).to(beNil())
                    expect(Optional<Int>.none.apRight(rhs: Optional<String>.none)).to(beNil())
                }
            }

            context("liftA2") {
                it("combines both values if both are present") {
                    expect(Optional(2).liftA2(Optional(3), +)).to(equal(5))
                }

                it("returns nil if one or both of the values are nil") {
                    expect(Optional(2).liftA2(Optional<Int>.none, +)).to(beNil())
                    expect(Optional<Int>.none.liftA2(Optional(3), +)).to(beNil())
                    expect(Optional<Int>.none.liftA2(Optional<Int>.none, +)).to(beNil())
                }
            }
        }
    }
}
