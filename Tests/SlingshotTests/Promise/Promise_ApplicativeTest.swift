import Testing
@testable import Slingshot

@Suite("Promise applicative")
struct Promise_ApplicativeTest {
    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both resolved values")
        func combinesBothResolvedValues() async {
            let result = await Promise.pure(2).liftA2(Promise.pure(3), +).value
            #expect(result == 5)
        }
    }
}
