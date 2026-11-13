/// freer monad effects, more akin to polysem than an actual freer monad implementation. every effect is async throws

/// A family of effects, and what it takes to run them.
public protocol EffectFamily {
    associatedtype Interpreter
}

/// A set of effect families a program can run in.
/// Only the types `@EffectFamily` and `@Effects` generate conform to it: don't conform to it by hand.
public protocol EffectStack: EffectFamily {}

/// One operation of a family, which its interpreter performs.
public protocol Effect<Family, Output> {
    associatedtype Family: EffectFamily
    associatedtype Output

    func accept(_ interpreter: Family.Interpreter) async throws -> Output
}

/// A program in `Family`'s effects that produces an `A`.
public indirect enum Freer<Family: EffectFamily, A> {
    case pure(A)
    /// An effect, or a sub-program, followed by the rest of the program
    case step(any FreerStep<Family, A>)
    /// Two programs that don't depend on each other, combined: an interpreter can see both before running either
    case both(any FreerBoth<Family, A>)
}

/// `∃x. (an effect or program producing x) × (x → Freer f a)`: the existential hides `x`.
public protocol FreerStep<Family, A> {
    associatedtype Family: EffectFamily
    associatedtype A

    func run(with interpreter: Family.Interpreter) async throws -> A
    func flatMap<B>(_ transform: @escaping (A) -> Freer<Family, B>) -> any FreerStep<Family, B>
    func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family
}

/// `∃x y. Freer f x × Freer f y × (x, y → a)`: the existential hides `x` and `y`.
public protocol FreerBoth<Family, A> {
    associatedtype Family: EffectFamily
    associatedtype A

    func run(with interpreter: Family.Interpreter) async throws -> A
    func map<B>(_ transform: @escaping (A) -> B) -> any FreerBoth<Family, B>
    func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family
}

/// An effect, then the rest of the program given its output.
public struct Bind<Family: EffectFamily, X, A>: FreerStep {
    public let effect: any Effect<Family, X>
    let next: (X) -> Freer<Family, A>

    public func run(with interpreter: Family.Interpreter) async throws -> A {
        let x = try await effect.accept(interpreter)
        return try await next(x).run(with: interpreter)
    }

    public func flatMap<B>(_ transform: @escaping (A) -> Freer<Family, B>) -> any FreerStep<Family, B> {
        Bind<Family, X, B>(effect: effect, next: { x in self.next(x).flatMap(transform) })
    }
    
    /// The effect becomes a program, and the rest is translated once it's reached
    public func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        translation.translate(effect).flatMap { x in self.next(x).translate(translation) }
    }
}

/// A whole sub-program, then the rest given its result: how a `both` is followed by more program.
struct Then<Family: EffectFamily, X, A>: FreerStep {
    let first: Freer<Family, X>
    let next: (X) -> Freer<Family, A>

    func run(with interpreter: Family.Interpreter) async throws -> A {
        let x = try await first.run(with: interpreter)
        return try await next(x).run(with: interpreter)
    }

    func flatMap<B>(_ transform: @escaping (A) -> Freer<Family, B>) -> any FreerStep<Family, B> {
        Then<Family, X, B>(first: first, next: { x in self.next(x).flatMap(transform) })
    }
    
    func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        first.translate(translation).flatMap { x in self.next(x).translate(translation) }
    }
}

/// Two independent programs and how to combine their results.
public struct Ap<Family: EffectFamily, X, Y, A>: FreerBoth {
    public let left: Freer<Family, X>
    public let right: Freer<Family, Y>
    let combine: (X, Y) -> A

    // In order, left then right: a concurrent interpreter is a separate piece of work
    public func run(with interpreter: Family.Interpreter) async throws -> A {
        let x = try await left.run(with: interpreter)
        let y = try await right.run(with: interpreter)
        return combine(x, y)
    }

    public func map<B>(_ transform: @escaping (A) -> B) -> any FreerBoth<Family, B> {
        Ap<Family, X, Y, B>(left: left, right: right, combine: { x, y in transform(self.combine(x, y)) })
    }
    
    /// Both sides are translated and stay a `both`: independence survives translation
    public func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        .both(Ap<T.To, X, Y, A>(left: left.translate(translation), right: right.translate(translation), combine: combine))
    }
}

public extension Freer {
    /// A program that performs one effect and returns its output
    static func perform(_ effect: any Effect<Family, A>) -> Freer<Family, A> {
        .step(Bind(effect: effect, next: { .pure($0) }))
    }

    func run(with interpreter: Family.Interpreter) async throws -> A {
        switch self {
        case .pure(let a):
            return a
        case .step(let step):
            return try await step.run(with: interpreter)
        case .both(let both):
            return try await both.run(with: interpreter)
        }
    }

    func flatMap<B>(_ transform: @escaping (A) -> Freer<Family, B>) -> Freer<Family, B> {
        switch self {
        case .pure(let a):
            transform(a)
        case .step(let step):
            .step(step.flatMap(transform))
        case .both:
            .step(Then(first: self, next: transform))
        }
    }

    func map<B>(_ transform: @escaping (A) -> B) -> Freer<Family, B> {
        switch self {
        case .pure(let a):
            .pure(transform(a))
        case .step(let step):
            .step(step.flatMap { .pure(transform($0)) })
        case .both(let both):
            .both(both.map(transform))
        }
    }
    
    /// Replaces every effect by a program in another family, keeping the result and the structure around it:
    /// `flatMap` for effects, where `flatMap` is for results
    func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        switch self {
        case .pure(let a):
            .pure(a)
        case .step(let step):
            step.translate(translation)
        case .both(let both):
            both.translate(translation)
        }
    }

    /// Keeps both programs visible as a `both`, instead of hiding the second behind a continuation like `flatMap`
    func liftA2<B, C>(_ other: Freer<Family, B>, _ f: @escaping (A, B) -> C) -> Freer<Family, C> {
        .both(Ap(left: self, right: other, combine: f))
    }
}

/// Replaces each effect of `From` by a program in `To` producing the same output: `∀x. f x → Freer g x`.
/// `@EffectFamily` generates a per-family `Translation` with one method per operation, which is easier to write.
public protocol Translation<From, To> {
    associatedtype From: EffectFamily
    associatedtype To: EffectFamily

    func translate<X>(_ effect: any Effect<From, X>) -> Freer<To, X>
}
