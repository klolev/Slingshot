/// The clock that timeouts and retry backoff wait on. It defaults to `ContinuousClock`;
/// provide another one, e.g. in tests, to control time without passing a clock to every call.
///
///     await Ambient.provide(AmbientClock(testClock)) { await work.retry(.exponential(initial: .seconds(1), maxAttempts: 3)).value }
public struct AmbientClock: AmbientValue {
    public static var defaultValue: AmbientClock {
        AmbientClock(ContinuousClock())
    }

    public let clock: any Clock<Duration>

    public init(_ clock: some Clock<Duration>) {
        self.clock = clock
    }

    /// Throws `CancellationError` if the task is cancelled while waiting
    public func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}
