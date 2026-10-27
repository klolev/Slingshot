public extension IO {
    func flatMap<C>(_ transform: @escaping (Value) -> IO<C>) -> IO<C> {
        IO<C> {
            let x = await self._f()
            return await transform(x).value
        }
    }
}
