import Testing
@testable import Slingshot

@Suite("Concurrently strategies")
struct Concurrently_StrategyTest {
    @Suite("width")
    struct Width {
        @Test("runs at most width children at a time and keeps the order")
        func runsAtMostWidthChildrenAtATimeAndKeepsTheOrder() async {
            let tracker = InFlight()
            let result = await Array(0..<6).traverse { tracked($0, tracker) }
                .using(.parallel(width: 2))
                .value
            #expect(result == Array(0..<6))
            #expect(await tracker.peak == 2)
        }

        @Test("sequential runs one child at a time")
        func sequentialRunsOneChildAtATime() async {
            let tracker = InFlight()
            _ = await Array(0..<3).traverse { tracked($0, tracker) }.using(.sequential).value
            #expect(await tracker.peak == 1)
        }

        @Test("a width below one still makes progress")
        func aWidthBelowOneStillMakesProgress() async {
            #expect(await [1, 2].traverse { Concurrently.pure($0) }.using(.parallel(width: 0)).value == [1, 2])
        }
    }

    @Suite("nesting")
    struct Nesting {
        @Test("nested traversals reuse the strategy by default")
        func nestedTraversalsReuseTheStrategyByDefault() async {
            let tracker = InFlight()
            _ = await Array(0..<3).traverse { _ in Array(0..<3).traverse { tracked($0, tracker) } }
                .using(.parallel(width: 2))
                .value
            #expect(await tracker.peak == 4)
        }

        @Test("then sets the strategy for nested traversals")
        func thenSetsTheStrategyForNestedTraversals() async {
            let tracker = InFlight()
            let result = await Array(0..<3).traverse { x in Array(0..<3).traverse { tracked(x * 3 + $0, tracker) } }
                .using(.parallel(width: 2).then(.sequential))
                .value
            #expect(result == [[0, 1, 2], [3, 4, 5], [6, 7, 8]])
            #expect(await tracker.peak == 2)
        }
    }

    @Suite("short-circuiting")
    struct ShortCircuiting {
        @Test("sequential never starts the elements after a failure")
        func sequentialNeverStartsTheElementsAfterAFailure() async {
            let starts = StartLog()
            let result = await Array(0..<4).traverse { index in
                Concurrently<Either<String, Int>> {
                    await starts.record(index)
                    return index == 1 ? .left("bad") : .right(index)
                }
            }
            .using(.sequential)
            .value
            #expect(result.left == "bad")
            #expect(await starts.indices == [0, 1])
        }

        @Test("nothing new starts after a failure, even while earlier elements run")
        func nothingNewStartsAfterAFailureEvenWhileEarlierElementsRun() async {
            let starts = StartLog()
            let result = await Array(0..<4).traverse { index in
                Concurrently<Either<String, Int>> {
                    await starts.record(index)
                    if index == 0 {
                        try? await Task.sleep(nanoseconds: 30_000_000)
                    }
                    return index == 1 ? .left("bad") : .right(index)
                }
            }
            .using(.parallel(width: 2))
            .value
            #expect(result.left == "bad")
            #expect(await starts.indices.sorted() == [0, 1])
        }
    }

    @Suite("task options")
    struct TaskOptions {
        @Test("children run with the strategy's priority")
        func childrenRunWithTheStrategysPriority() async {
            // basePriority is what the task was created with; currentPriority can be escalated by the waiting parent
            let priorities = await [0].traverse { _ in Concurrently { Task.basePriority } }
                .using(Strategy.parallel.priority(.high))
                .value
            #expect(priorities == [.high])
        }

        @Test("children run with the strategy's name")
        func childrenRunWithTheStrategysName() async {
            guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
            let names = await [0].traverse { _ in Concurrently { Task.name } }
                .using(Strategy.parallel.named("fetch"))
                .value
            #expect(names == ["fetch"])
        }

        @Test("the strategy outside using is parallel")
        func theStrategyOutsideUsingIsParallel() {
            #expect(Strategy.current.width == nil)
        }
    }
}

/// Records which elements started, in order.
actor StartLog {
    private(set) var indices: [Int] = []

    func record(_ index: Int) {
        indices.append(index)
    }
}
