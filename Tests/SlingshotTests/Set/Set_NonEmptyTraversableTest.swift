import Quick
import Nimble
@testable import Slingshot

class Set_NonEmptyTraversableTest: QuickSpec {
    override func spec() {
        describe("Set.NonEmpty Traversable") {
            let elements = Array(1...50)
            // `first` is a member of the set, but deliberately not the one iteration starts with
            let set = Set(elements)
            let ne = Set<Int>.NonEmpty(first: set.dropFirst().first!, container: set)

            context("traverse (Optional)") {
                it("visits every element exactly once") {
                    var visited: [Int] = []
                    let result = ne.traverse { x -> Int? in visited.append(x); return x * 2 }
                    expect(visited.sorted()).to(equal(elements))
                    expect(result?.erased).to(equal(Set(elements.map { $0 * 2 })))
                }

                it("returns nil when any transform fails") {
                    let result = ne.traverse { $0 == 50 ? nil : .some($0) }
                    expect(result).to(beNil())
                }
            }

            context("traverse (Validation)") {
                it("accumulates a failure for every element") {
                    let result: Validation<String, Set<Int>.NonEmpty> = ne.traverse { .fail("e\($0)") }
                    expect(result.failures.sorted()).to(equal(elements.map { "e\($0)" }.sorted()))
                }
            }
        }
    }
}
