public typealias Predicate<T> = (T) -> Bool

public func keypath<T>(_ keypath: KeyPath<T, Bool>) -> Predicate<T> {
    { $0[keyPath: keypath] }
}

public func not<T>(_ predicate: @escaping Predicate<T>) -> Predicate<T> {
    { !predicate($0) }
}

public func && <T>(lhs: @escaping Predicate<T>, rhs: @escaping Predicate<T>) -> Predicate<T> {
    { lhs($0) && rhs($0) }
}

public func || <T>(lhs: @escaping Predicate<T>, rhs: @escaping Predicate<T>) -> Predicate<T> {
    { lhs($0) || rhs($0) }
}

/// Whether the value at `keyPath` equals `value`, `equals(\.status, .active)`
public func equals<T, V: Equatable>(_ keyPath: KeyPath<T, V>, _ value: V) -> Predicate<T> {
    { $0[keyPath: keyPath] == value }
}

/// Tests other values by what `transform` gives for them, `contramap(isValidEmail, \.email)`
public func contramap<T, V>(_ predicate: @escaping Predicate<V>, _ transform: @escaping (T) -> V) -> Predicate<T> {
    { predicate(transform($0)) }
}

/// Holds when every predicate does, so it holds for an empty list
public func allOf<T>(_ predicates: [Predicate<T>]) -> Predicate<T> {
    { value in predicates.allSatisfy { $0(value) } }
}

public func allOf<T>(_ predicates: Predicate<T>...) -> Predicate<T> {
    allOf(predicates)
}

/// Holds when at least one predicate does, so it never holds for an empty list
public func anyOf<T>(_ predicates: [Predicate<T>]) -> Predicate<T> {
    { value in predicates.contains { $0(value) } }
}

public func anyOf<T>(_ predicates: Predicate<T>...) -> Predicate<T> {
    anyOf(predicates)
}

/// Holds when no predicate does, so it holds for an empty list
public func noneOf<T>(_ predicates: [Predicate<T>]) -> Predicate<T> {
    not(anyOf(predicates))
}

public func noneOf<T>(_ predicates: Predicate<T>...) -> Predicate<T> {
    noneOf(predicates)
}
