import Quick
import Nimble
@testable import Slingshot

class Set_TraversableTest: QuickSpec {
    override func spec() {
        describe("Set Traversable") {
            context("traverse (Optional)") {
                it("returns some when all transforms succeed") {
                    let result = Set([1, 2, 3]).traverse { $0 > 0 ? .some($0 * 2) : nil }
                    expect(result).to(equal(Set([2, 4, 6])))
                }

                it("returns nil when any transform fails") {
                    let result = Set([1, -1, 3]).traverse { $0 > 0 ? .some($0 * 2) : nil }
                    expect(result).to(beNil())
                }

                it("returns some empty set for empty input") {
                    let result = Set<Int>().traverse { Optional.some($0) }
                    expect(result).to(equal(Set()))
                }
            }

            context("traverse (Result)") {
                it("returns success when all transforms succeed") {
                    let result: Result<Set<Int>, TestError> = Set([1, 2, 3]).traverse { .success($0 * 2) }
                    expect(result).to(equal(.success(Set([2, 4, 6]))))
                }

                it("returns failure when any transform fails") {
                    let result: Result<Set<Int>, TestError> = Set([1, 2, 3]).traverse { $0 == 2 ? .failure(.bad) : .success($0) }
                    expect(result).to(equal(.failure(.bad)))
                }
            }

            context("traverse (Either)") {
                it("returns right when all transforms succeed") {
                    let result: Either<String, Set<Int>> = Set([1, 2, 3]).traverse { .right($0 * 2) }
                    expect(result.right).to(equal(Set([2, 4, 6])))
                }

                it("returns left on first failure") {
                    let result: Either<String, Set<Int>> = Set([1]).traverse { _ in Either<String, Int>.left("fail") }
                    expect(result.left).to(equal("fail"))
                }
            }

            context("traverse (Validation)") {
                it("returns success when all succeed") {
                    let result: Validation<String, Set<Int>> = Set([1, 3]).traverse { .success($0) }
                    expect(result.value).to(equal(Set([1, 3])))
                }

                it("accumulates failures") {
                    let result: Validation<String, Set<Int>> = Set([1]).traverse { .fail("err\($0)") }
                    expect(result.failures).to(equal(["err1"]))
                }
            }

            context("sequenced (Set<Optional>)") {
                it("returns some set when all elements are some") {
                    let input: Set<Int?> = [.some(1), .some(2), .some(3)]
                    expect(input.sequenced).to(equal(Set([1, 2, 3])))
                }

                it("returns nil when any element is nil") {
                    let input: Set<Int?> = [.some(1), .none]
                    expect(input.sequenced).to(beNil())
                }

                it("returns some empty set for empty input") {
                    let input: Set<Int?> = []
                    expect(input.sequenced).to(equal(Set()))
                }
            }
        }
    }
}
