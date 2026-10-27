import Testing
@testable import Slingshot

@Suite("Concurrently applicative")
struct Concurrently_ApplicativeTest {
    @Suite("liftA2")
    struct LiftA2 {
        @Test("combines both resolved values")
        func combinesBothResolvedValues() async {
            let result = await Concurrently.pure(2).liftA2(Concurrently.pure(3), +).value
            #expect(result == 5)
        }

        @Test("runs both sides at the same time")
        func runsBothSidesAtTheSameTime() async {
            let tracker = InFlight()
            _ = await tracked(1, tracker).liftA2(tracked(2, tracker), +).value
            #expect(await tracker.peak == 2)
        }
    }

    @Suite("ap")
    struct Ap {
        @Test("applies the resolved function to the resolved value")
        func appliesTheResolvedFunctionToTheResolvedValue() async {
            let double: Concurrently<@Sendable (Int) -> Int> = .pure { $0 * 2 }
            let result = await Concurrently.ap(double)(.pure(21)).value
            #expect(result == 42)
        }
    }

    @Suite("apLeft / apRight")
    struct ApLeftRight {
        @Test("keep the value from their side")
        func keepTheValueFromTheirSide() async {
            #expect(await Concurrently.pure(1).apLeft(rhs: .pure("a")).value == 1)
            #expect(await Concurrently.pure(1).apRight(rhs: .pure("a")).value == "a")
        }
    }

    @Suite("io")
    struct ToIO {
        @Test("resolves to the same value in IO")
        func resolvesToTheSameValueInIO() async {
            let result = await Concurrently.pure(2).io.flatMap { x in IO.pure(x + 1) }.value
            #expect(result == 3)
        }
    }
}

@Suite("Concurrently alternative")
struct Concurrently_AlternativeTest {
    @Test("race returns whichever side finishes first")
    func raceReturnsWhicheverSideFinishesFirst() async {
        let slow = Concurrently<Int> {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return 0
        }
        let fast = Concurrently.pure(1)
        #expect(await slow.race(fast).value == 1)
        #expect(await fast.alt(slow).value == 1)
    }
}

/// Records the most computations that were ever running at once.
actor InFlight {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

/// A computation that resolves to `x` after a short delay, reporting to `tracker` while it runs.
func tracked<T: Sendable>(_ x: T, _ tracker: InFlight, delayNanoseconds: UInt64 = 50_000_000) -> Concurrently<T> {
    Concurrently {
        await tracker.enter()
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        await tracker.leave()
        return x
    }
}
