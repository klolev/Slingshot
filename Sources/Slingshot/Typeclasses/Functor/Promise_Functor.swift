public extension Promise {
    func map<C>(_ transform: @escaping (Value) -> C) -> Promise<C> {
        Promise<C> {
            transform(await self._f())
        }
    }
}
