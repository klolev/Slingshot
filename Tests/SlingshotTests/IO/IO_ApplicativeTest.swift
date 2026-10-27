import Testing
@testable import Slingshot

@Suite("IO applicative")
struct IO_ApplicativeTest {
    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both resolved values")
        func combinesBothResolvedValues() async {
            let result = await IO.pure(2).liftA2(IO.pure(3), +).value
            #expect(result == 5)
        }
    }
}
