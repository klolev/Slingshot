public extension IO {
    func map<C>(_ transform: @escaping (Value) -> C) -> IO<C> {
        IO<C> {
            transform(await self._f())
        }
    }
}
