import Foundation
import Testing
@testable import Slingshot

@Suite("IO isolation")
struct IO_IsolationTest {
    @Test("non-Sendable values can be awaited from the main actor")
    @MainActor
    func nonSendableValuesCanBeAwaitedFromTheMainActor() async {
        let counter = Counter()
        let io = IO { counter }
            .map { counter in counter.increment() }
            .flatMap { count in IO { count + counter.count } }
        #expect(await io.value == 2)
    }

    @Test("traversals of non-Sendable values can be awaited from the main actor")
    @MainActor
    func traversalsOfNonSendableValuesCanBeAwaitedFromTheMainActor() async {
        let counter = Counter()
        let counts = await [1, 2, 3].traverse { _ in IO { counter.increment() } }.value
        #expect(counts == [1, 2, 3])
    }

    // The compiler can't see where a stored closure runs, so check at runtime that every closure ran on the awaiting actor's executor
    @Test("every closure runs on the awaiting actor")
    func everyClosureRunsOnTheAwaitingActor() async {
        let observations = await QueueActor().observeIO()
        #expect(observations == [true, true, true, true, true, true])
    }
}

/// A non-Sendable reference, so the tests fail to compile if IO sends it off the main actor.
final class Counter {
    private(set) var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

/// An actor whose executor is a tagged queue, so code can check whether it's running on that actor.
actor QueueActor {
    private let executor = QueueExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func observeIO() async -> [Bool] {
        let onActor = { QueueExecutor.isCurrent }
        let io = IO { [onActor()] }
            .map { $0 + [onActor()] }
            .flatMap { xs in IO { xs + [onActor()] } }
            .liftA2(IO { onActor() }) { $0 + [$1] }
        let traversed = [0, 1].traverse { _ in IO { onActor() } }
        return await io.value + traversed.value
    }
}

final class QueueExecutor: SerialExecutor {
    private static let key = DispatchSpecificKey<Bool>()
    private let queue = DispatchQueue(label: "QueueExecutor")

    init() {
        queue.setSpecific(key: Self.key, value: true)
    }

    static var isCurrent: Bool {
        DispatchQueue.getSpecific(key: key) == true
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
