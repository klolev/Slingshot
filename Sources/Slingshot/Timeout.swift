public extension Concurrently {
    /// The value, or `nil` when it takes longer than `duration` on the ambient clock; the slower side is cancelled.
    /// Cancellation is cooperative, like `race`: a `nil` only arrives once the work notices it was cancelled.
    func timeout(after duration: Duration) -> Concurrently<Value?> {
        map { .some($0) }.race(Concurrently<Value?> {
            // Cancelled when the work wins, and the race ignores the loser's result
            try? await Ambient.ask(AmbientClock.self).sleep(for: duration)
            return nil
        })
    }
}
