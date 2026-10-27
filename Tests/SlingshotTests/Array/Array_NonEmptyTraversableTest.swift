import Quick
import Nimble
@testable import Slingshot

class Array_NonEmptyTraversableTest: QuickSpec {
    override func spec() {
        describe("Array.NonEmpty Traversable") {
            context("traverse (Optional)") {
                it("returns some nonempty when all transforms succeed") {
                    let ne = [Int].NonEmpty(first: 1, 2, 3)
                    let result = ne.traverse { .some($0 * 2) }
                    expect(result?.first).to(equal(2))
                    expect(result?.erased).to(equal([2, 4, 6]))
                }

                it("returns nil when any transform fails") {
                    let ne = [Int].NonEmpty(first: 1, 2, 3)
                    let result = ne.traverse { $0 == 2 ? nil : .some($0) }
                    expect(result).to(beNil())
                }
            }

            context("traverse (Result)") {
                it("returns success nonempty when all succeed") {
                    let ne = [Int].NonEmpty(first: 10, 20)
                    let result: Result<[Int].NonEmpty, TestError> = ne.traverse { .success($0 + 1) }
                    expect(try result.get().erased).to(equal([11, 21]))
                }

                it("returns failure when any fails") {
                    let ne = [Int].NonEmpty(first: 1, 2)
                    let result: Result<[Int].NonEmpty, TestError> = ne.traverse { _ in .failure(.bad) }
                    expect(result).to(equal(.failure(.bad)))
                }
            }

            context("traverse (Either)") {
                it("returns right nonempty when all succeed") {
                    let ne = [Int].NonEmpty(first: 5, 6)
                    let result: Either<String, [Int].NonEmpty> = ne.traverse { .right($0 * 3) }
                    expect(result.right?.erased).to(equal([15, 18]))
                }

                it("returns left on failure") {
                    let ne = [Int].NonEmpty(first: 1)
                    let result: Either<String, [Int].NonEmpty> = ne.traverse { _ in .left("no") }
                    expect(result.left).to(equal("no"))
                }
            }

            context("traverse (Validation)") {
                it("returns success when all succeed") {
                    let ne = [Int].NonEmpty(first: 1, 2)
                    let result: Validation<String, [Int].NonEmpty> = ne.traverse { .success($0 * 10) }
                    expect(result.value?.erased).to(equal([10, 20]))
                }

                it("accumulates failures") {
                    let ne = [Int].NonEmpty(first: 1, 2, 3)
                    let result: Validation<String, [Int].NonEmpty> = ne.traverse { .fail("e\($0)") }
                    expect(result.failures).to(equal(["e1", "e2", "e3"]))
                }
            }

            context("traverse visits each element exactly once") {
                it("follows the container when it does not start with first") {
                    let ne = [Int].NonEmpty(first: 0, container: [5, 6])
                    var visited: [Int] = []
                    let result = ne.traverse { x -> Int? in visited.append(x); return x }
                    expect(visited).to(equal([5, 6]))
                    expect(result?.erased).to(equal([5, 6]))
                }
            }
        }
    }
}
