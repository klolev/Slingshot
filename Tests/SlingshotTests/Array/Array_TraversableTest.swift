import Foundation
import Quick
import Nimble
@testable import Slingshot

class Array_TraversableTest: QuickSpec {
    override func spec() {
        describe("Array Traversable") {
            context("sequenced ([T?])") {
                it("returns some empty array when the array is empty") {
                    expect(Array<Int?>.zero.sequenced).to(equal([]))
                }

                it("returns none when the array contains a none value") {
                    expect([0, nil].sequenced).to(beNil())
                    expect([Optional<Int>.none].sequenced).to(beNil())
                    expect([nil, 0].sequenced).to(beNil())
                }

                it("returns some array when the array contains a no none values") {
                    expect([Optional.some(0), 1].sequenced).to(equal([0, 1]))
                    expect([Optional.some(0)].sequenced).to(equal([0]))
                    expect([Optional.some(Optional.some(0))].sequenced).to(equal([Optional.some(0)]))
                }
            }

            context("traverse (Optional)") {
                it("returns some when all transforms succeed") {
                    let result = [1, 2, 3].traverse { $0 > 0 ? .some($0 * 2) : nil }
                    expect(result).to(equal([2, 4, 6]))
                }

                it("returns nil when any transform fails") {
                    let result = [1, -1, 3].traverse { $0 > 0 ? .some($0 * 2) : nil }
                    expect(result).to(beNil())
                }

                it("returns some empty array for empty input") {
                    let result = [Int]().traverse { Optional.some($0) }
                    expect(result).to(equal([]))
                }
            }

            context("traverse (Result)") {
                it("returns success when all transforms succeed") {
                    let result: Result<[Int], TestError> = [1, 2, 3].traverse { .success($0 * 2) }
                    expect(result).to(equal(.success([2, 4, 6])))
                }

                it("returns failure when any transform fails") {
                    let result: Result<[Int], TestError> = [1, 2, 3].traverse { $0 == 2 ? .failure(.bad) : .success($0) }
                    expect(result).to(equal(.failure(.bad)))
                }

                it("returns success empty for empty input") {
                    let result: Result<[Int], TestError> = [Int]().traverse { .success($0) }
                    expect(result).to(equal(.success([])))
                }
            }

            context("traverse (Validation)") {
                it("returns success when all transforms succeed") {
                    let result: Validation<String, [Int]> = [1, 2, 3].traverse { .success($0 * 2) }
                    expect(result.value).to(equal([2, 4, 6]))
                }

                it("accumulates all failures") {
                    let result: Validation<String, [Int]> = [1, 2, 3].traverse {
                        $0 % 2 == 0 ? .fail("even: \($0)") : .success($0)
                    }
                    expect(result.failures).to(equal(["even: 2"]))
                }

                it("accumulates multiple failures") {
                    let result: Validation<String, [Int]> = [2, 4, 6].traverse { .fail("bad: \($0)") }
                    expect(result.failures).to(equal(["bad: 2", "bad: 4", "bad: 6"]))
                }
            }

            context("traverse (Either)") {
                it("returns right when all transforms succeed") {
                    let result: Either<String, [Int]> = [1, 2, 3].traverse { .right($0 * 2) }
                    expect(result.right).to(equal([2, 4, 6]))
                }

                it("returns left on first failure") {
                    let result: Either<String, [Int]> = [1, 2, 3].traverse {
                        $0 == 2 ? .left("fail") : .right($0)
                    }
                    expect(result.left).to(equal("fail"))
                }
            }

            context("sequenced ([Result])") {
                it("returns success when all elements are success") {
                    let input: [Result<Int, TestError>] = [.success(1), .success(2), .success(3)]
                    expect(input.sequenced).to(equal(.success([1, 2, 3])))
                }

                it("returns failure when any element is failure") {
                    let input: [Result<Int, TestError>] = [.success(1), .failure(.bad), .success(3)]
                    expect(input.sequenced).to(equal(.failure(.bad)))
                }
            }

            context("sequenced ([Either])") {
                it("returns right when all elements are right") {
                    let input: [Either<String, Int>] = [.right(1), .right(2)]
                    expect(input.sequenced.right).to(equal([1, 2]))
                }

                it("returns left on first left") {
                    let input: [Either<String, Int>] = [.right(1), .left("oops")]
                    expect(input.sequenced.left).to(equal("oops"))
                }
            }

            context("traverse (Promise)") {
                it("resolves to the transformed values in order") {
                    waitUntil { done in
                        Task {
                            let result = await [1, 2, 3].traverse { Promise.pure($0 * 2) }.value
                            expect(result).to(equal([2, 4, 6]))
                            done()
                        }
                    }
                }

                it("handles large inputs without overflowing the stack") {
                    let input = Array(0..<100_000)
                    waitUntil(timeout: .seconds(10)) { done in
                        Task {
                            let result = await input.traverse { Promise.pure($0) }.value
                            expect(result).to(equal(input))
                            done()
                        }
                    }
                }
            }
        }
    }
}

enum TestError: Error, Equatable {
    case bad
}
