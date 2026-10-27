#if Macros
import Testing
@testable import Slingshot

@Suite("#do")
struct DoTest {
    @Suite("monads")
    struct Monads {
        @Test("Optional threads dependent binds")
        func optionalThreadsDependentBinds() {
            let total: Int? = #do { bind in
                let a = bind(Int("4"))
                let b = bind(Int("\(a)2"))
                return a + b
            }
            #expect(total == 46)
        }

        @Test("Optional stops at the first nil")
        func optionalStopsAtTheFirstNil() {
            let total: Int? = #do { bind in
                let a = bind(Int("x"))
                let b = bind(Int("\(a)"))
                return a + b
            }
            #expect(total == nil)
        }

        @Test("Array is the list monad")
        func arrayIsTheListMonad() {
            let pairs: [Int] = #do { bind in
                let x = bind([1, 2])
                let y = bind(Array(repeating: x, count: x))
                return x * 10 + y
            }
            #expect(pairs == [11, 22, 22])
        }

        @Test("Reader reads the dependency in every bind")
        func readerReadsTheDependencyInEveryBind() {
            let reader: Reader<Int, Int> = #do { bind in
                let a = bind(Reader<Int, Int> { $0 + 1 })
                let b = bind(Reader<Int, Int> { $0 * a })
                return a + b
            }
            #expect(reader.execute(with: 10) == 121)
        }

        @Test("Either returns the first left")
        func eitherReturnsTheFirstLeft() {
            let result: Either<String, Int> = #do { bind in
                let a = bind(Either<String, Int>.right(1))
                let b = bind(Either<String, Int>.left("bad \(a)"))
                return a + b
            }
            #expect(result.left == "bad 1")
        }
    }

    @Suite("applicative do")
    struct ApplicativeDo {
        @Test("independent Validation binds collect every error")
        func independentValidationBindsCollectEveryError() {
            let result: Validation<String, Int> = #do { bind in
                let a = bind(Validation<String, Int>.fail("a"))
                let b = bind(Validation<String, Int>.fail("b"))
                return a + b
            }
            #expect(result.failures == ["a", "b"])
        }

        @Test("independent Concurrently binds run at the same time")
        func independentConcurrentlyBindsRunAtTheSameTime() async {
            let tracker = InFlight()
            let sum: Concurrently<Int> = #do { bind in
                let a = bind(tracked(1, tracker))
                let b = bind(tracked(2, tracker))
                let c = bind(tracked(3, tracker))
                return a + b + c
            }
            #expect(await sum.value == 6)
            #expect(await tracker.peak == 3)
        }

        @Test("plain statements between independent binds keep them independent")
        func plainStatementsBetweenIndependentBindsKeepThemIndependent() async {
            let validated: Validation<String, Int> = #do { bind in
                let a = bind(Validation<String, Int>.fail("a"))
                let k = 3
                let b = bind(Validation<String, Int>.fail("b"))
                return a + b + k
            }
            #expect(validated.failures == ["a", "b"])

            let tracker = InFlight()
            let sum: Concurrently<Int> = #do { bind in
                let a = bind(tracked(1, tracker))
                let doubled = a * 2
                let b = bind(tracked(2, tracker))
                return doubled + b
            }
            #expect(await sum.value == 4)
            #expect(await tracker.peak == 2)
        }

        @Test("a bind using a plain statement's name waits for it")
        func aBindUsingAPlainStatementsNameWaitsForIt() {
            let result: Int? = #do { bind in
                let a = bind(Optional(4))
                let next = a + 1
                let b = bind(Int("\(next)"))
                return a + b
            }
            #expect(result == 9)
        }

        @Test("an early return stops later binds from running")
        func anEarlyReturnStopsLaterBindsFromRunning() {
            let result: Int? = #do { bind in
                let a = bind(Optional(2))
                if a > 1 { return 0 }
                let b = bind(Optional<Int>.none)
                return a + b
            }
            #expect(result == 0)
        }

        @Test("Array cross product matches the monadic one")
        func arrayCrossProductMatchesTheMonadicOne() {
            let sums: [Int] = #do { bind in
                let x = bind([1, 2])
                let y = bind([10, 20])
                return x + y
            }
            #expect(sums == [11, 21, 12, 22])
        }
    }

    @Suite("nesting")
    struct Nesting {
        @Test("a nested block can reuse the binder's name and see outer binds")
        func aNestedBlockCanReuseTheBindersNameAndSeeOuterBinds() {
            let result: Int? = #do { bind in
                let a = bind(Optional(1))
                let b = bind(#do { bind in
                    let x = bind(Optional(a + 1))
                    return x * 10
                } as Int?)
                return a + b
            }
            #expect(result == 21)
        }

        @Test("a nested block can use another type")
        func aNestedBlockCanUseAnotherType() async {
            let io: IO<Int?> = #do { bind in
                let a = bind(IO.pure(2))
                let parsed: Int? = #do { bind in
                    let x = bind(Int("\(a)1"))
                    return x + 1
                }
                return parsed
            }
            #expect(await io.value == 22)
        }

        @Test("a failing nested block fails the outer one")
        func aFailingNestedBlockFailsTheOuterOne() {
            let result: Int? = #do { bind in
                let a = bind(Optional(1))
                let b = bind(#do { bind in
                    let x = bind(Int("nope"))
                    return x + a
                } as Int?)
                return a + b
            }
            #expect(result == nil)
        }
    }

    @Suite("statements")
    struct Statements {
        @Test("plain statements, patterns and annotations are kept")
        func plainStatementsPatternsAndAnnotationsAreKept() {
            let result: Int? = #do { bind in
                let (a, b) = bind(Optional((1, 2)))
                let doubled = a * 2
                var c: Int = bind(Optional(doubled + b))
                c += 1
                return c
            }
            #expect(result == 5)
        }

        @Test("a final return bind is the last step")
        func aFinalReturnBindIsTheLastStep() {
            let result: Int? = #do { bind in
                let a = bind(Optional(2))
                return bind(a > 1 ? Optional(a * 10) : nil)
            }
            #expect(result == 20)
        }

        @Test("a block without binds is pure")
        func aBlockWithoutBindsIsPure() {
            let result: [Int] = #do { _ in
                let x = 2
                return x * 3
            }
            #expect(result == [6])
        }
    }
}
#endif
