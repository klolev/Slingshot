import Foundation
import Testing
@testable import Slingshot

@Suite("UnsignedInteger Sequence")
struct UnsignedInteger_SequenceTest {
    @Suite("sequence")
    struct Sequence {
        @Test("acts as a range from 0 to the specified number")
        func actsAsARangeFrom0ToTheSpecifiedNumber() {
            #expect(UInt(3).map(identity) == [0, 1, 2])
        }

        @Test("returns an empty array when the number is 0")
        func returnsAnEmptyArrayWhenTheNumberIs0() {
            #expect(UInt(0).map(identity) == [])
        }
    }
}
