import Testing
@testable import Slingshot

@Suite("Concurrently timeout and retry")
struct Concurrently_TimeTest {
    @Suite("timeout")
    struct Timeout {
        @Test("returns the value when the work finishes in time")
        func returnsTheValueWhenTheWorkFinishesInTime() async {
            #expect(await Concurrently.pure(1).timeout(after: .seconds(10)).value == 1)
        }


        @Test("returns nil and cancels the work when it takes too long")
        func returnsNilAndCancelsTheWorkWhenItTakesTooLong() async {
            let log = CancellationLog()
            let result = await sleeper(0, 1, nanoseconds: 10_000_000_000, log).timeout(after: .milliseconds(50)).value
            #expect(result == nil)
            #expect(await log.cancelled == [0])
        }


        @Test("waits on the ambient clock")
        func waitsOnTheAmbientClock() async {
            let clock = ImmediateClock()
            let log = CancellationLog()
            let result = await Ambient.provide(AmbientClock(clock)) {
                await sleeper(0, 1, nanoseconds: 10_000_000_000, log).timeout(after: .seconds(30)).value
            }
            #expect(result == nil)
            #expect(await clock.sleeps.durations == [.seconds(30)])
        }
    }

    @Suite("retry")
    struct Retry {
        @Test("retries until the work succeeds")
        func retriesUntilTheWorkSucceeds() async {
            let clock = ImmediateClock()
            let attempts = Attempts()
            let result = await Ambient.provide(AmbientClock(clock)) {
                await failing(until: 3, attempts).retry(.constant(.seconds(1), maxAttempts: 5)).value
            }
            #expect(result == .success(3))
            #expect(await attempts.count == 3)
            #expect(await clock.sleeps.durations == [.seconds(1), .seconds(1)])
        }


        @Test("returns the last failure once the attempts run out")
        func returnsTheLastFailureOnceTheAttemptsRunOut() async {
            let clock = ImmediateClock()
            let attempts = Attempts()
            let result = await Ambient.provide(AmbientClock(clock)) {
                await failing(until: 10, attempts).retry(.immediate(maxAttempts: 3)).value
            }
            #expect(result == .failure(.bad))
            #expect(await attempts.count == 3)
        }


        @Test("stops when shouldRetry declines")
        func stopsWhenShouldRetryDeclines() async {
            let attempts = Attempts()
            let result = await failing(until: 10, attempts).retry(.immediate(maxAttempts: 3), while: { _ in false }).value
            #expect(result == .failure(.bad))
            #expect(await attempts.count == 1)
        }


        @Test("always makes at least one attempt")
        func alwaysMakesAtLeastOneAttempt() async {
            let attempts = Attempts()
            _ = await failing(until: 10, attempts).retry(.immediate(maxAttempts: 0)).value
            #expect(await attempts.count == 1)
        }


        @Test("retries an Either while it's a left")
        func retriesAnEitherWhileItsALeft() async {
            let attempts = Attempts()
            let work = Concurrently<Either<String, Int>> {
                let attempt = await attempts.next()
                return attempt < 2 ? .left("no") : .right(attempt)
            }
            #expect(await work.retry(.immediate(maxAttempts: 3)).value.right == 2)
        }


        @Test("waits on the ambient clock between attempts")
        func waitsOnTheAmbientClockBetweenAttempts() async {
            let clock = ImmediateClock()
            let attempts = Attempts()
            _ = await Ambient.provide(AmbientClock(clock)) {
                await failing(until: 10, attempts)
                    .retry(.exponential(initial: .seconds(1), maxDelay: .seconds(4), maxAttempts: 5))
                    .value
            }
            #expect(await clock.sleeps.durations == [.seconds(1), .seconds(2), .seconds(4), .seconds(4)])
        }
    }

    @Suite("RetryPolicy")
    struct Policy {
        @Test("exponential delays grow up to the cap")
        func exponentialDelaysGrowUpToTheCap() {
            let policy = RetryPolicy.exponential(initial: .milliseconds(100), multiplier: 3, maxDelay: .seconds(1), maxAttempts: 5)
            #expect((1...4).map(policy.delay(beforeRetry:)) == [.milliseconds(100), .milliseconds(300), .milliseconds(900), .seconds(1)])
        }


        @Test("jittered delays stay within the delay")
        func jitteredDelaysStayWithinTheDelay() {
            let policy = RetryPolicy.constant(.seconds(2), maxAttempts: 3).jittered()
            for _ in 0..<100 {
                let delay = policy.delay(beforeRetry: 1)
                #expect(delay >= .zero && delay <= .seconds(2))
            }
        }
    }
}

/// Fails with `.bad` until attempt `success`, then succeeds with the attempt number.
func failing(until success: Int, _ attempts: Attempts) -> Concurrently<Result<Int, TestError>> {
    Concurrently {
        let attempt = await attempts.next()
        return attempt < success ? .failure(.bad) : .success(attempt)
    }
}

actor Attempts {
    private(set) var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

/// A clock whose sleeps return at once, recording how long they were asked to wait.
struct ImmediateClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    let sleeps = SleepLog()

    var now: Instant { Instant(offset: .zero) }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await sleeps.record(deadline.offset)
    }
}

actor SleepLog {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}
