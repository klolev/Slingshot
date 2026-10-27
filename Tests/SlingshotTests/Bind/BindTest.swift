import Testing
@testable import Slingshot

@Suite("run / bind")
struct BindTest {
    @Suite("Optional")
    struct OptionalRun {
        @Test("returns the block's value when every bind succeeds")
        func returnsTheBlocksValueWhenEveryBindSucceeds() {
            let total: Int? = Optional.run {
                let a = try Int("4").bind()
                let b = try Int("2").bind()
                return a + b
            }
            #expect(total == 6)
        }

        @Test("returns nil at the first nil and skips the rest")
        func returnsNilAtTheFirstNilAndSkipsTheRest() {
            var reached = false
            let total: Int? = Optional.run {
                let a = try Int("x").bind()
                reached = true
                return a
            }
            #expect(total == nil)
            #expect(!reached)
        }

        @Test("other errors also become nil")
        func otherErrorsAlsoBecomeNil() {
            let value: Int? = Optional.run { throw TestError.bad }
            #expect(value == nil)
        }

        @Test("works with ordinary control flow")
        func worksWithOrdinaryControlFlow() {
            let sum: Int? = Optional.run {
                var sum = 0
                for text in ["1", "2", "3"] {
                    sum += try Int(text).bind()
                }
                return sum
            }
            #expect(sum == 6)
        }

        @Test("async blocks can await")
        func asyncBlocksCanAwait() async {
            let value: Int? = await Optional.run {
                let a = try await IO.pure(Optional(1)).value.bind()
                return a + 1
            }
            #expect(value == 2)
        }
    }

    @Suite("Either")
    struct EitherRun {
        @Test("returns right when every bind succeeds")
        func returnsRightWhenEveryBindSucceeds() throws {
            let result: Either<String, Int> = try Either.run {
                let a = try Either<String, Int>.right(1).bind()
                let b = try Either<String, Int>.right(2).bind()
                return a + b
            }
            #expect(result.right == 3)
        }

        @Test("returns the first left")
        func returnsTheFirstLeft() throws {
            let result: Either<String, Int> = try Either.run {
                let a = try Either<String, Int>.left("first").bind()
                let b = try Either<String, Int>.left("second").bind()
                return a + b
            }
            #expect(result.left == "first")
        }

        @Test("carries non-Sendable lefts")
        func carriesNonSendableLefts() throws {
            final class Problem { let reason = "bad" }
            let result: Either<Problem, Int> = try Either.run {
                try Either<Problem, Int>.left(Problem()).bind()
            }
            #expect(result.left?.reason == "bad")
        }

        @Test("rethrows errors that aren't a failed bind")
        func rethrowsErrorsThatArentAFailedBind() {
            #expect(throws: TestError.bad) {
                let _: Either<String, Int> = try Either.run { throw TestError.bad }
            }
        }
    }

    @Suite("Result")
    struct ResultRun {
        @Test("returns the first failure")
        func returnsTheFirstFailure() throws {
            let result: Result<Int, TestError> = try Result.run {
                let a = try Result<Int, TestError>.success(1).bind()
                let b = try Result<Int, TestError>.failure(.bad).bind()
                return a + b
            }
            #expect(result == .failure(.bad))
        }

        @Test("async blocks can await")
        func asyncBlocksCanAwait() async throws {
            let result: Result<Int, TestError> = try await Result.run {
                try await IO.pure(Result<Int, TestError>.success(3)).value.bind()
            }
            #expect(result == .success(3))
        }
    }
}
