import Quick
import Nimble
@testable import Slingshot

class Optional_FoldableTest: QuickSpec {
    override func spec() {
        describe("Optional foldable") {
            context("reduce") {
                it("returns initial when value is nil") {
                    expect(Optional<Int>.none.reduce("a") { result, value in
                        result + String(value)
                    }).to(equal("a"))
                }

                it("returns result when value is present") {
                    expect(Optional<Int>.some(3).reduce("a") { result, value in
                        result + String(value)
                    }).to(equal("a3"))
                }
            }

            context("reduce into") {
                it("returns initial when value is nil") {
                    expect(Optional<Int>.none.reduce(into: []) { result, value in
                        result.append(value)
                    }).to(equal([]))
                }

                it("returns result when value is present") {
                    expect(Optional<Int>.some(3).reduce(into: []) { result, value in
                        result.append(value)
                    }).to(equal([3]))
                }
            }
        }
    }
}
