import Quick
import Nimble
@testable import Slingshot

class Promise_ApplicativeTest: QuickSpec {
    override func spec() {
        describe("Promise applicative") {
            context("liftA2") {
                it("combines both resolved values") {
                    waitUntil { done in
                        Task {
                            let result = await Promise.pure(2).liftA2(Promise.pure(3), +).value
                            expect(result).to(equal(5))
                            done()
                        }
                    }
                }
            }
        }
    }
}
