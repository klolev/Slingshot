import Testing
@testable import Slingshot

@Suite("Optional foldable")
struct Optional_FoldableTest {
    @Suite("reduce")
    struct Reduce {
        @Test("returns initial when value is nil")
        func returnsInitialWhenValueIsNil() {
            #expect(Optional<Int>.none.reduce("a") { result, value in
                result + String(value)
            } == "a")
        }

        @Test("returns result when value is present")
        func returnsResultWhenValueIsPresent() {
            #expect(Optional<Int>.some(3).reduce("a") { result, value in
                result + String(value)
            } == "a3")
        }
    }

    @Suite("reduce into")
    struct ReduceInto {
        @Test("returns initial when value is nil")
        func returnsInitialWhenValueIsNil() {
            #expect(Optional<Int>.none.reduce(into: []) { result, value in
                result.append(value)
            } == [])
        }

        @Test("returns result when value is present")
        func returnsResultWhenValueIsPresent() {
            #expect(Optional<Int>.some(3).reduce(into: []) { result, value in
                result.append(value)
            } == [3])
        }
    }
}
