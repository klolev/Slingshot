/// How `retry` reruns failing work: how many attempts in total, and how long to wait before each retry.
/// Like `Strategy`, it only changes how the work runs: the result is still one attempt's result.
///
///     work.retry(.exponential(initial: .milliseconds(100), maxDelay: .seconds(5), maxAttempts: 5).jittered())
public struct RetryPolicy: Sendable {
    /// Attempts in total, counting the first; at least one attempt is always made
    public var maxAttempts: Int
    /// The wait before the first retry
    public var initialDelay: Duration
    /// How much each wait grows over the one before
    public var multiplier: Double
    /// The longest any wait can grow to
    public var maxDelay: Duration?
    /// Whether each wait is a random fraction of its delay ("full jitter"), so many clients don't retry in lockstep
    public var jitter: Bool

    public init(maxAttempts: Int, initialDelay: Duration = .zero, multiplier: Double = 1, maxDelay: Duration? = nil, jitter: Bool = false) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    public static func immediate(maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(maxAttempts: maxAttempts)
    }

    public static func constant(_ delay: Duration, maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(maxAttempts: maxAttempts, initialDelay: delay)
    }

    public static func exponential(initial: Duration, multiplier: Double = 2, maxDelay: Duration? = nil, maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(maxAttempts: maxAttempts, initialDelay: initial, multiplier: multiplier, maxDelay: maxDelay)
    }

    public func jittered() -> RetryPolicy {
        var copy = self
        copy.jitter = true
        return copy
    }

    /// The wait before retry number `retry`, counting from 1
    public func delay(beforeRetry retry: Int) -> Duration {
        var delay = initialDelay * Double.pow(multiplier, retry - 1)
        if let maxDelay, delay > maxDelay {
            delay = maxDelay
        }
        return jitter ? delay * Double.random(in: 0...1) : delay
    }
}

private extension Double {
    static func pow(_ base: Double, _ exponent: Int) -> Double {
        (0..<max(exponent, 0)).reduce(1) { result, _ in result * base }
    }
}

public extension Concurrently {
    /// Runs the work again while it fails and `shouldRetry` agrees, waiting on the ambient clock between attempts.
    /// Returns the first success, or the last failure once the attempts run out or the task is cancelled.
    func retry<Success, Failure>(_ policy: RetryPolicy,
                                 while shouldRetry: @escaping @Sendable (Failure) -> Bool = { _ in true }) -> Concurrently<Result<Success, Failure>>
    where Value == Result<Success, Failure> {
        retrying(policy) { result in
            if case .failure(let failure) = result, shouldRetry(failure) { true } else { false }
        }
    }

    /// Runs the work again while it's a `left` and `shouldRetry` agrees, waiting on the ambient clock between attempts.
    /// Returns the first `right`, or the last `left` once the attempts run out or the task is cancelled.
    func retry<L, R>(_ policy: RetryPolicy,
                     while shouldRetry: @escaping @Sendable (L) -> Bool = { _ in true }) -> Concurrently<Either<L, R>>
    where Value == Either<L, R> {
        retrying(policy) { either in
            if case .left(let left) = either, shouldRetry(left) { true } else { false }
        }
    }

    private func retrying(_ policy: RetryPolicy, while shouldRetry: @escaping @Sendable (Value) -> Bool) -> Concurrently<Value> {
        Concurrently {
            let clock = Ambient.ask(AmbientClock.self)
            var attempt = 1
            while true {
                let value = await self.value
                guard attempt < policy.maxAttempts, shouldRetry(value), !Task.isCancelled else {
                    return value
                }
                do {
                    try await clock.sleep(for: policy.delay(beforeRetry: attempt))
                } catch {
                    // Cancelled while waiting
                    return value
                }
                attempt += 1
            }
        }
    }
}
