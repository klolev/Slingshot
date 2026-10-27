import Testing
@testable import Slingshot

// AsyncStream can't fail, so it gets the overloads without the stream's Result; `throwingStream` covers the ones with it.
@Suite("Concurrently over AsyncSequence")
struct Concurrently_AsyncSequenceTest {
    @Suite("mapConcurrently")
    struct MapConcurrently {
        @Test("keeps input order and runs at most width at a time")
        func keepsInputOrderAndRunsAtMostWidthAtATime() async {
            let tracker = InFlight()
            var values: [Int] = []
            for await value in [0, 1, 2, 3, 4, 5].asyncStream.mapConcurrently(.parallel(width: 2), { x in
                tracked(x * 10, tracker, delayNanoseconds: UInt64(6 - x) * 5_000_000)
            }) {
                values.append(value)
            }
            #expect(values == [0, 10, 20, 30, 40, 50])
            #expect(await tracker.peak == 2)
        }

        @Test("unordered results come as they finish")
        func unorderedResultsComeAsTheyFinish() async {
            let tracker = InFlight()
            var values: [Int] = []
            for await value in [0, 1, 2].asyncStream.mapConcurrently(.parallel, ordered: false, { x in
                tracked(x, tracker, delayNanoseconds: UInt64(2 - x) * 40_000_000)
            }) {
                values.append(value)
            }
            #expect(values == [2, 1, 0])
        }

        @Test("stopping early cancels the work still running")
        func stoppingEarlyCancelsTheWorkStillRunning() async throws {
            let log = CancellationLog()
            for await _ in [0, 1, 2].asyncStream.mapConcurrently(.parallel, { index in
                index == 0 ? Concurrently.pure(index) : sleeper(index, index, nanoseconds: 10_000_000_000, log)
            }) {
                break
            }
            try await waitForCancellations(2, in: log)
            #expect(await log.cancelled.sorted() == [1, 2])
        }

        @Test("each element's work runs under the inner strategy")
        func eachElementsWorkRunsUnderTheInnerStrategy() async {
            let tracker = InFlight()
            for await _ in [0, 1, 2].asyncStream.mapConcurrently(.parallel(width: 2).then(.sequential), { _ in
                [0, 1, 2].traverse { tracked($0, tracker) }
            }) {}
            #expect(await tracker.peak == 2)
        }

        @Test("the work sees ambient values")
        func theWorkSeesAmbientValues() async {
            let values = await Ambient.provide(AmbientTest.Config(scale: 7)) {
                var values: [Int] = []
                for await value in [1, 2].asyncStream.mapConcurrently(.parallel, { x in
                    Concurrently { x * Ambient.ask(AmbientTest.Config.self).scale }
                }) {
                    values.append(value)
                }
                return values
            }
            #expect(values == [7, 14])
        }

        @Test("a stream that can fail keeps order and width")
        func aStreamThatCanFailKeepsOrderAndWidth() async throws {
            let tracker = InFlight()
            var values: [Int] = []
            for try await value in throwingStream([0, 1, 2, 3]).mapConcurrently(.parallel(width: 2), { x in
                tracked(x, tracker, delayNanoseconds: UInt64(4 - x) * 5_000_000)
            }) {
                values.append(value)
            }
            #expect(values == [0, 1, 2, 3])
            #expect(await tracker.peak == 2)
        }

        @Test("a stream that can fail cancels the work still running when stopped early")
        func aStreamThatCanFailCancelsTheWorkStillRunningWhenStoppedEarly() async throws {
            let log = CancellationLog()
            for try await _ in throwingStream([0, 1]).mapConcurrently(.parallel, { index in
                index == 0 ? Concurrently.pure(index) : sleeper(index, index, nanoseconds: 10_000_000_000, log)
            }) {
                break
            }
            try await waitForCancellations(1, in: log)
            #expect(await log.cancelled == [1])
        }

        @Test("a stream's typed error is rethrown with its type")
        func aStreamsTypedErrorIsRethrownWithItsType() async {
            do throws(TestError) {
                for try await _ in TypedFailingStream(values: [1], failure: .bad).mapConcurrently(.parallel, { Concurrently.pure($0) }) {}
                Issue.record("expected the stream's error")
            } catch {
                #expect(error == .bad)
            }
        }

        @Test("it can be iterated from the main actor")
        @MainActor
        func itCanBeIteratedFromTheMainActor() async {
            var values: [Int] = []
            for await value in [1, 2].asyncStream.mapConcurrently(.parallel(width: 1), { Concurrently.pure($0 * 3) }) {
                values.append(value)
            }
            #expect(values == [3, 6])
        }

        @Test("errors from the stream are rethrown")
        func errorsFromTheStreamAreRethrown() async {
            let stream = AsyncThrowingStream<Int, any Error> { continuation in
                continuation.yield(1)
                continuation.finish(throwing: TestError.bad)
            }
            await #expect(throws: TestError.bad) {
                for try await _ in stream.mapConcurrently(.parallel, { Concurrently.pure($0) }) {}
            }
        }
    }

    @Suite("traverse")
    struct Traverse {
        @Test("collects every result in order")
        func collectsEveryResultInOrder() async {
            #expect(await [1, 2, 3].asyncStream.traverse { Concurrently.pure($0 * 2) }.value == [2, 4, 6])
        }

        @Test("follows the strategy it runs with")
        func followsTheStrategyItRunsWith() async {
            let tracker = InFlight()
            _ = await [0, 1, 2].asyncStream.traverse { tracked($0, tracker) }.using(.sequential).value
            #expect(await tracker.peak == 1)
        }

        @Test("a stream that can fail wraps the results in its Result")
        func aStreamThatCanFailWrapsTheResultsInItsResult() async throws {
            let result = await throwingStream([1, 2, 3]).traverse { Concurrently.pure($0 * 2) }.value
            #expect(try result.get() == [2, 4, 6])
        }

        @Test("returns a typed stream error with its type")
        func returnsATypedStreamErrorWithItsType() async {
            let result: Result<[Int], TestError> = await TypedFailingStream(values: [1], failure: .bad).traverse { Concurrently.pure($0) }.value
            #expect(result == .failure(.bad))
        }

        @Test("returns the stream's error")
        func returnsTheStreamsError() async {
            let stream = AsyncThrowingStream<Int, any Error> { $0.finish(throwing: TestError.bad) }
            let result = await stream.traverse { Concurrently.pure($0) }.value
            #expect(throws: TestError.bad) { try result.get() }
        }
    }

    @Suite("short-circuiting traverse")
    struct ShortCircuitingTraverse {
        @Test("returns every right when nothing fails")
        func returnsEveryRightWhenNothingFails() async {
            let result = await [1, 2].asyncStream.traverse { Concurrently.pure(Either<String, Int>.right($0)) }.value
            #expect(result.right == [1, 2])
        }

        @Test("returns the first left in input order, not the first to finish")
        func returnsTheFirstLeftInInputOrderNotTheFirstToFinish() async {
            let log = CancellationLog()
            let result = await [0, 1].asyncStream.traverse { index in
                sleeper(index, Either<String, Int>.left("left \(index)"), nanoseconds: index == 0 ? 40_000_000 : 0, log)
            }.value
            #expect(result.left == "left 0")
        }

        @Test("stops reading the stream after a failure")
        func stopsReadingTheStreamAfterAFailure() async {
            let starts = StartLog()
            let result = await [0, 1, 2, 3].asyncStream.traverse { index in
                recordingStart(index, starts, failingAt: 1)
            }
            .using(.sequential)
            .value
            #expect(result.left == "bad")
            #expect(await starts.indices == [0, 1])
        }

        @Test("cancels the work still running after a failure")
        func cancelsTheWorkStillRunningAfterAFailure() async throws {
            let log = CancellationLog()
            let result = await [0, 1].asyncStream.traverse { index in
                index == 0
                    ? Concurrently.pure(Either<String, Int>.left("bad"))
                    : sleeper(index, .right(index), nanoseconds: 10_000_000_000, log)
            }.value
            #expect(result.left == "bad")
            try await waitForCancellations(1, in: log)
            #expect(await log.cancelled == [1])
        }

        @Test("Result returns the first failure, typed")
        func resultReturnsTheFirstFailureTyped() async {
            let result: Result<[Int], TestError> = await [1, 2, 3].asyncStream.traverse { x in
                Concurrently.pure(x == 2 ? Result<Int, TestError>.failure(.bad) : .success(x))
            }.value
            #expect(result == .failure(.bad))
        }

        @Test("Optional is nil when any element is nil")
        func optionalIsNilWhenAnyElementIsNil() async {
            #expect(await [1, 2].asyncStream.traverse { Concurrently.pure(Optional($0)) }.value == [1, 2])
            #expect(await [1, 2].asyncStream.traverse { x in Concurrently.pure(x == 2 ? nil : Optional(x)) }.value == nil)
        }

        @Test("a stream that can fail returns the first left in input order")
        func aStreamThatCanFailReturnsTheFirstLeftInInputOrder() async throws {
            let log = CancellationLog()
            let result = await throwingStream([0, 1]).traverse { index in
                sleeper(index, Either<String, Int>.left("left \(index)"), nanoseconds: index == 0 ? 40_000_000 : 0, log)
            }.value
            #expect(try result.get().left == "left 0")
        }

        @Test("a stream that can fail stops being read after a failure")
        func aStreamThatCanFailStopsBeingReadAfterAFailure() async throws {
            let starts = StartLog()
            let result = await throwingStream([0, 1, 2, 3]).traverse { index in
                recordingStart(index, starts, failingAt: 1)
            }
            .using(.sequential)
            .value
            #expect(try result.get().left == "bad")
            #expect(await starts.indices == [0, 1])
        }

        @Test("a stream that can fail nests Result and Optional inside its Result")
        func aStreamThatCanFailNestsResultAndOptionalInsideItsResult() async throws {
            let result = await throwingStream([1, 2]).traverse { x in
                Concurrently.pure(x == 2 ? Result<Int, TestError>.failure(.bad) : .success(x))
            }.value
            let optional = await throwingStream([1, 2]).traverse { Concurrently.pure(Optional($0)) }.value
            #expect(try result.get() == .failure(.bad))
            #expect(try optional.get() == [1, 2])
        }

        @Test("the stream's own error is the outer failure")
        func theStreamsOwnErrorIsTheOuterFailure() async {
            let stream = AsyncThrowingStream<Int, any Error> { $0.finish(throwing: TestError.bad) }
            let result = await stream.traverse { Concurrently.pure(Either<String, Int>.right($0)) }.value
            #expect(throws: TestError.bad) { try result.get() }
        }
    }
}

/// A stream that could fail but doesn't, to exercise the overloads that wrap results in the stream's Result.
func throwingStream(_ values: [Int]) -> AsyncThrowingStream<Int, any Error> {
    AsyncThrowingStream { continuation in
        for value in values {
            continuation.yield(value)
        }
        continuation.finish()
    }
}

/// Records that element `index` started, and fails it at `failingAt`.
func recordingStart(_ index: Int, _ starts: StartLog, failingAt failure: Int) -> Concurrently<Either<String, Int>> {
    Concurrently {
        await starts.record(index)
        return index == failure ? .left("bad") : .right(index)
    }
}

/// Cancelled stream work finishes in the background, so give it a moment to report.
func waitForCancellations(_ count: Int, in log: CancellationLog) async throws {
    for _ in 0..<200 where await log.cancelled.count < count {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// A stream that fails with a concrete error type after its values.
struct TypedFailingStream: AsyncSequence, Sendable {
    typealias Element = Int
    typealias Failure = TestError

    let values: [Int]
    let failure: TestError

    func makeAsyncIterator() -> Iterator {
        Iterator(values: values, failure: failure)
    }

    struct Iterator: AsyncIteratorProtocol {
        var values: [Int]
        let failure: TestError

        mutating func next() async throws(TestError) -> Int? {
            guard !values.isEmpty else { throw failure }
            return values.removeFirst()
        }
    }
}
