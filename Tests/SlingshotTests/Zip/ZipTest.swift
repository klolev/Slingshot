import Testing
@testable import Slingshot

@Suite("zip builders")
struct ZipTest {
    @Suite("Optional")
    struct OptionalZip {
        @Test("collects every value into a flat tuple")
        func collectsEveryValueIntoAFlatTuple() {
            let zipped = Optional.zip {
                Int("1")
                Optional("a")
                Optional(2.5)
            }
            #expect(zipped.map { "\($0)\($1)\($2)" } == "1a2.5")
        }

        @Test("is nil when any statement is nil")
        func isNilWhenAnyStatementIsNil() {
            let zipped = Optional.zip {
                Int("1")
                Int("x")
            }
            #expect(zipped == nil)
        }

        @Test("a single statement is just its value")
        func aSingleStatementIsJustItsValue() {
            #expect(Optional.zip { Int("3") } == 3)
        }
    }

    @Suite("Result and Either")
    struct ShortCircuiting {
        @Test("Result returns the first failure in order")
        func resultReturnsTheFirstFailureInOrder() {
            let zipped = Result.zip {
                Result<Int, TestError>.success(1)
                Result<String, TestError>.failure(.bad)
            }
            #expect(zipped.map { "\($0)\($1)" } == .failure(.bad))
        }

        @Test("Either returns the first left in order")
        func eitherReturnsTheFirstLeftInOrder() {
            let zipped = Either.zip {
                Either<String, Int>.left("first")
                Either<String, Bool>.left("second")
            }
            #expect(zipped.left == "first")
        }
    }

    @Suite("Validation")
    struct ValidationZip {
        @Test("collects every error")
        func collectsEveryError() {
            let zipped = Validation.zip {
                Validation<String, Int>.fail("name")
                Validation<String, Int>.success(3)
                Validation<String, Bool>.fail("age")
            }
            #expect(zipped.failures == ["name", "age"])
        }

        @Test("succeeds with every value")
        func succeedsWithEveryValue() {
            let zipped = Validation.zip {
                Validation<String, Int>.success(1)
                Validation<String, String>.success("b")
            }
            #expect(zipped.value.map { "\($0)\($1)" } == "1b")
        }
    }

    @Suite("IO")
    struct IOZip {
        @Test("runs the statements one after another")
        func runsTheStatementsOneAfterAnother() async {
            let log = Log()
            let zipped = IO.zip {
                IO { log.record("a"); return 1 }
                IO { log.record("b"); return "two" }
            }
            let (one, two) = await zipped.value
            #expect(one == 1 && two == "two")
            #expect(log.entries == ["a", "b"])
        }
    }

    @Suite("Concurrently")
    struct ConcurrentlyZip {
        @Test("runs every statement at the same time")
        func runsEveryStatementAtTheSameTime() async {
            let tracker = InFlight()
            let joined = await Concurrently.zip {
                tracked(1, tracker)
                tracked("b", tracker)
                tracked(true, tracker)
            }
            .map { n, s, b in "\(n)\(s)\(b)" }
            .value
            #expect(joined == "1btrue")
            #expect(await tracker.peak == 3)
        }

        @Test("follows the strategy")
        func followsTheStrategy() async {
            let tracker = InFlight()
            _ = await Concurrently.zip {
                tracked(1, tracker)
                tracked(2, tracker)
            }
            .using(.sequential)
            .value
            #expect(await tracker.peak == 1)
        }
    }
}

/// A non-Sendable record of what ran, in order.
final class Log {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}
