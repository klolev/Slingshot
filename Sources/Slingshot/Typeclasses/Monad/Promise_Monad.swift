public extension Promise {
    func flatMap<C>(_ transform: @escaping (Value) -> Promise<C>) -> Promise<C> {
        Promise<C> {
            let x = await self._f()
            return await transform(x).value
        }
    }
}
