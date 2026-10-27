public extension Concurrently {
    /// Returns whichever computation finishes first and cancels the other.
    /// Cancellation is cooperative: the result is only ready once the loser notices it was cancelled and returns.
    func race(_ other: Concurrently<Value>) -> Concurrently<Value> {
        Concurrently {
            await withTaskGroup(of: Value.self) { group in
                group.addTask { await self.value }
                group.addTask { await other.value }
                // Two tasks were added, so the group can't be empty
                let winner = await group.next()!
                group.cancelAll()
                return winner
            }
        }
    }
}

extension Concurrently: Alternative {
    public func alt(_ x: Concurrently<Value>) -> Concurrently<Value> {
        race(x)
    }
}
