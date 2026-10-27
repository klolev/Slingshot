import Testing
@testable import Slingshot

@Suite("Optional functor")
struct Optional_FunctorTest {
    @Suite("map")
    struct Map {
        @Test("maps its value when some")
        func mapsItsValueWhenSome() {
            #expect(Optional.some(1).map { $0 + 1 } == 2)
        }

        @Test("maps to nil when its value is none")
        func mapsToNilWhenItsValueIsNone() {
            #expect(Optional.none.map { $0 + 1 } == nil)
        }
    }

    @Suite("replace")
    struct Replace {
        @Test("replaces its value when some")
        func replacesItsValueWhenSome() {
            #expect(Optional.some(1).replace(with: 2) == 2)
        }

        @Test("stays nil if its value is none")
        func staysNilIfItsValueIsNone() {
            #expect(Optional<Int>.none.replace(with: 2) == nil)
        }
    }
}
