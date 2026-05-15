#if canImport(SwiftUI)
import SwiftUI

public extension Binding {
    func invmap<T>(_ transform: @escaping (Value) -> T, _ transformBack: @escaping (T) -> Value) -> Binding<T> {
        .init(get: { transform(self.wrappedValue) },
              set: { value in self.wrappedValue = transformBack(value) })
    }
}
#endif
