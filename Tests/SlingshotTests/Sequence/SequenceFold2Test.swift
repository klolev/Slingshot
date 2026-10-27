import Foundation
import Testing
@testable import Slingshot

@Suite("Sequence fold2")
struct SequenceFold2Test {
    @Suite("when using consumeBoth")
    struct WhenUsingConsumeBoth {
        @Test("consumes all elements of both arrays when both are the same length")
        func consumesAllElementsOfBothArraysWhenBothAreTheSameLength() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2, 3],
                                                        right: ["a", "b", "c"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeBoth
            }

            #expect(result == [.init(1, "a"), .init(2, "b"), .init(3, "c")])
        }

        @Test("consumes all elements of the first array and the corresponding items from second array when the first array is shorter")
        func consumesAllElementsOfTheFirstArrayAndTheCorrespondingItemsFromSecondArrayWhenTheFirstArrayIsShorter() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2],
                                                        right: ["a", "b", "c"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeBoth
            }

            #expect(result == [.init(1, "a"), .init(2, "b")])
        }

        @Test("consumes all elements of the second array and the corresponding items from from array when the second array is shorter")
        func consumesAllElementsOfTheSecondArrayAndTheCorrespondingItemsFromFromArrayWhenTheSecondArrayIsShorter() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2, 3],
                                                        right: ["a", "b"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeBoth
            }

            #expect(result == [.init(1, "a"), .init(2, "b")])
        }

        @Test("consumes nothing when the first array is empty")
        func consumesNothingWhenTheFirstArrayIsEmpty() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: Array<Double>(),
                                                        right: ["a", "b"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeBoth
            }

            #expect(result.isEmpty)
        }

        @Test("consumes nothing when the second array is empty")
        func consumesNothingWhenTheSecondArrayIsEmpty() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2],
                                                        right: Array<String>()) { output, left, right in
                output.append(.init(left, right))
                return .consumeBoth
            }

            #expect(result.isEmpty)
        }

        @Test("consumes nothing when both arrays are empty")
        func consumesNothingWhenBothArraysAreEmpty() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: Array<Double>(),
                                                        right: Array<String>()) { output, left, right in
                output.append(.init(left, right))
                return .consumeBoth
            }

            #expect(result.isEmpty)
        }
    }

    @Suite("when using consumeLeft")
    struct WhenUsingConsumeLeft {
        @Test("consumes all elements of the first array when both are the same length")
        func consumesAllElementsOfTheFirstArrayWhenBothAreTheSameLength() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2, 3],
                                                        right: ["a", "b", "c"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeLeft
            }

            #expect(result == [.init(1, "a"), .init(2, "a"), .init(3, "a")])
        }

        @Test("consumes all elements of the first array when it is longer than the second one")
        func consumesAllElementsOfTheFirstArrayWhenItIsLongerThanTheSecondOne() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2, 3],
                                                        right: ["a", "b"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeLeft
            }

            #expect(result == [.init(1, "a"), .init(2, "a"), .init(3, "a")])
        }

        @Test("consumes nothing when the second array is empty")
        func consumesNothingWhenTheSecondArrayIsEmpty() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2, 3],
                                                        right: Array<String>()) { output, left, right in
                output.append(.init(left, right))
                return .consumeLeft
            }

            #expect(result.isEmpty)
        }
    }

    @Suite("when using consumeRight")
    struct WhenUsingConsumeRight {
        @Test("consumes all elements of the second array when both are the same length")
        func consumesAllElementsOfTheSecondArrayWhenBothAreTheSameLength() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2, 3],
                                                        right: ["a", "b", "c"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeRight
            }

            #expect(result == [.init(1, "a"), .init(1, "b"), .init(1, "c")])
        }

        @Test("consumes all elements of the second array when it is longer than the first one")
        func consumesAllElementsOfTheSecondArrayWhenItIsLongerThanTheFirstOne() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: [1, 2],
                                                        right: ["a", "b", "c"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeRight
            }

            #expect(result == [.init(1, "a"), .init(1, "b"), .init(1, "c")])
        }

        @Test("consumes nothing when the first array is empty")
        func consumesNothingWhenTheFirstArrayIsEmpty() {
            let result: [Tuple<Double, String>] = fold2(initial: [],
                                                        left: Array<Double>(),
                                                        right: ["a"]) { output, left, right in
                output.append(.init(left, right))
                return .consumeRight
            }

            #expect(result.isEmpty)
        }
    }
}
