import Quick
import Nimble
@testable import Slingshot

class Optional_TraversableTest: QuickSpec {
    override func spec() {
        describe("Optional Traversable") {
            context("traverse (Optional)") {
                it("returns nested some when value present and transform succeeds") {
                    let result: Optional<Int>? = Optional.some(3).traverse { .some($0 * 2) }
                    expect(result).to(equal(.some(.some(6))))
                }

                it("returns some none when value present but transform returns nil") {
                    let result = Optional.some(3).traverse { _ -> Int? in nil }
                    expect(result).to(beNil())
                }

                it("returns some none when value is nil") {
                    let result: Optional<Int>? = Optional<Int>.none.traverse { .some($0 * 2) }
                    expect(result).to(equal(.some(.none)))
                }
            }

            context("traverse (Result)") {
                it("returns success some when value present and transform succeeds") {
                    let result: Result<Int?, TestError> = Optional.some(3).traverse { .success($0 * 2) }
                    expect(result).to(equal(.success(.some(6))))
                }

                it("returns failure when value present and transform fails") {
                    let result: Result<Int?, TestError> = Optional.some(3).traverse { _ in Result<Int, TestError>.failure(.bad) }
                    expect(result).to(equal(.failure(.bad)))
                }

                it("returns success nil when value is nil") {
                    let result: Result<Int?, TestError> = Optional<Int>.none.traverse { .success($0) }
                    expect(result).to(equal(.success(nil)))
                }
            }

            context("traverse (Either)") {
                it("returns right some when value present and transform returns right") {
                    let result: Either<String, Int?> = Optional.some(5).traverse { .right($0 + 1) }
                    expect(result.right).to(equal(.some(6)))
                }

                it("returns left when value present and transform returns left") {
                    let result: Either<String, Int?> = Optional.some(5).traverse { _ in Either<String, Int>.left("nope") }
                    expect(result.left).to(equal("nope"))
                }

                it("returns right nil when value is nil") {
                    let result: Either<String, Int?> = Optional<Int>.none.traverse { .right($0) }
                    expect(result.right ?? .some(99)).to(beNil())
                }
            }

            context("sequenced (Optional<Result>)") {
                it("returns success some when some success") {
                    let input: Result<Int, TestError>? = .some(.success(42))
                    expect(input.sequenced).to(equal(.success(.some(42))))
                }

                it("returns failure when some failure") {
                    let input: Result<Int, TestError>? = .some(.failure(.bad))
                    expect(input.sequenced).to(equal(.failure(.bad)))
                }

                it("returns success nil when nil") {
                    let input: Result<Int, TestError>? = nil
                    expect(input.sequenced).to(equal(.success(nil)))
                }
            }

            context("sequenced (Optional<Either>)") {
                it("returns right some when some right") {
                    let input: Either<String, Int>? = .some(.right(10))
                    expect(input.sequenced.right).to(equal(.some(10)))
                }

                it("returns left when some left") {
                    let input: Either<String, Int>? = .some(.left("err"))
                    expect(input.sequenced.left).to(equal("err"))
                }

                it("returns right nil when nil") {
                    let input: Either<String, Int>? = nil
                    expect(input.sequenced.right ?? .some(99)).to(beNil())
                }
            }
        }
    }
}
