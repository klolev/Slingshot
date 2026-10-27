import Quick
import Nimble
@testable import Slingshot

class String_TraversableTest: QuickSpec {
    override func spec() {
        describe("String Traversable") {
            let upper: (Character) -> Character = { Character($0.uppercased()) }

            context("traverse (Optional)") {
                it("returns the transformed string when all transforms succeed") {
                    expect("abc".traverse { $0.isLetter ? upper($0) : nil }).to(equal("ABC"))
                }

                it("returns nil when any transform fails") {
                    expect("a1c".traverse { $0.isLetter ? upper($0) : nil }).to(beNil())
                }

                it("returns some empty string for empty input") {
                    expect("".traverse { Optional.some($0) }).to(equal(""))
                }
            }

            context("traverse (Result)") {
                it("returns the first failure") {
                    let result: Result<String, TestError> = "a1c2".traverse { $0.isLetter ? .success($0) : .failure(.bad) }
                    expect(result).to(equal(.failure(.bad)))
                }
            }

            context("traverse (Validation)") {
                it("accumulates a failure for every rejected character") {
                    let result: Validation<Character, String> = "a1c2".traverse { $0.isLetter ? .success(upper($0)) : .fail($0) }
                    expect(result.failures).to(equal(["1", "2"]))
                }
            }

            context("traverse (Either)") {
                it("returns right with the transformed string") {
                    let result: Either<String, String> = "abc".traverse { .right(upper($0)) }
                    expect(result.right).to(equal("ABC"))
                }
            }

            context("traverse (Promise)") {
                it("resolves to the transformed string") {
                    waitUntil { done in
                        Task {
                            let result = await "abc".traverse { Promise.pure(upper($0)) }.value
                            expect(result).to(equal("ABC"))
                            done()
                        }
                    }
                }
            }

            context("Substring") {
                it("traverses into a Substring") {
                    let result: Substring? = "xabcx".dropFirst().dropLast().traverse { upper($0) }
                    expect(result).to(equal("ABC"))
                }
            }

            context("Array keeping its element type") {
                it("still resolves to an array") {
                    let result: [Int]? = [1, 2, 3].traverse { .some($0 * 2) }
                    expect(result).to(equal([2, 4, 6]))
                    expect([1, 2, 3].traverse { Optional.some($0 * 2) }).to(equal([2, 4, 6]))
                }
            }
        }
    }
}
