#if canImport(SwiftUI)
import SwiftUI

public extension Binding where Value: Sendable {
    func invmap<T>(_ transform: @escaping @Sendable (Value) -> T, _ transformBack: @escaping @Sendable (T) -> Value) -> Binding<T> {
        .init(get: { transform(self.wrappedValue) },
              set: { value in self.wrappedValue = transformBack(value) })
    }
}
#endif
