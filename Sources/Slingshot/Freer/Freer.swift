/// freer monad effects, more akin to polysem than an actual freer monad implementation. every effect is async throws
///
/// The protocols here suppress Copyable on associated types (SE-0503). A generic `E: Effect` then means a copyable
/// `E.Output` unless it says `where E.Output: ~Copyable`, so every generic use that can see a noncopyable output says so.
///
/// Programs are noncopyable, and so can be the values they produce: a program runs once, and each step hands its result
/// to the next as a `consuming` parameter, so a noncopyable value (a session, a key) moves through it without being copied.
/// A program's steps that hold existentials are enums, bound with `switch consume`: consuming a noncopyable existential
/// stored property directly trips a compiler bug in Swift 6.4 ("copy of noncopyable typed value").

/// A family of effects, and what it takes to run them.
public protocol EffectFamily {
    associatedtype Interpreter
}

/// A set of effect families a program can run in.
/// Only the types `@EffectFamily` and `@Effects` generate, and `NoEffects`, conform to it: don't conform to it by hand.
public protocol EffectStack: EffectFamily {}

/// The stack with no families: its programs are pure, so `hoist` moves them into any stack.
public enum NoEffects: EffectStack {
    public typealias Interpreter = Void

    public static func hoist<Target: EffectStack, V: ~Copyable>(_ program: consuming Freer<NoEffects, V>, into target: Target.Type) -> Freer<Target, V> {
        program.translate(Hoisting<Target>())
    }

    struct Hoisting<Target: EffectStack>: Translation {
        typealias From = NoEffects
        typealias To = Target

        func translate<X: ~Copyable>(_ effect: consuming any Effect<NoEffects, X> & ~Copyable) -> Freer<Target, X> {
            preconditionFailure("an effect claims NoEffects as its family, which has no effects")
        }
    }
}

/// One operation of a family, which its interpreter performs.
/// An effect runs once, so it can carry noncopyable inputs and produce a noncopyable output.
public protocol Effect<Family, Output>: ~Copyable {
    associatedtype Family: EffectFamily
    associatedtype Output: ~Copyable

    consuming func accept(_ interpreter: Family.Interpreter) async throws -> Output

    /// Hands the effect to a translation written per operation, like an `@EffectFamily`'s `Translation`.
    /// `@EffectFamily` implements it for its effects; no other effect is ever translated this way.
    consuming func translated<Translating: FamilyTranslation>(with translation: Translating) -> Freer<Translating.Target, Output>
}

public extension Effect where Self: ~Copyable, Output: ~Copyable {
    consuming func translated<Translating: FamilyTranslation>(with translation: Translating) -> Freer<Translating.Target, Output> {
        preconditionFailure("\(Self.self) isn't an operation of an @EffectFamily, so a family's translation can't translate it")
    }
}

/// What every `@EffectFamily`'s `Translation` protocol refines: a translation into programs in `Target`.
public protocol FamilyTranslation {
    associatedtype Target: EffectFamily
}

/// A program in `Family`'s effects that produces an `A`.
public enum Freer<Family: EffectFamily, A: ~Copyable>: ~Copyable {
    case pure(A)
    /// An effect, or a sub-program, followed by the rest of the program
    case step(any FreerStep<Family, A> & ~Copyable)
    /// Two programs that don't depend on each other, combined: an interpreter can see both before running either
    case both(any FreerBoth<Family, A> & ~Copyable)
}

/// `∃x. (an effect or program producing x) × (x → Freer f a)`: the existential hides `x`.
public protocol FreerStep<Family, A>: ~Copyable {
    associatedtype Family: EffectFamily
    associatedtype A: ~Copyable

    /// Runs this step's effect or sub-program, and returns the rest of the program instead of running it:
    /// `Freer.run` loops over steps, so a long or recursive program runs at constant depth
    consuming func advance(with interpreter: Family.Interpreter) async throws -> Freer<Family, A>
    consuming func flatMap<B: ~Copyable>(_ transform: @escaping (consuming A) -> Freer<Family, B>) -> any FreerStep<Family, B> & ~Copyable
    consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family
}

/// `∃x y. Freer f x × Freer f y × (x, y → a)`: the existential hides `x` and `y`.
public protocol FreerBoth<Family, A>: ~Copyable {
    associatedtype Family: EffectFamily
    associatedtype A: ~Copyable

    consuming func run(with interpreter: Family.Interpreter) async throws -> A
    consuming func map<B: ~Copyable>(_ transform: @escaping (consuming A) -> B) -> any FreerBoth<Family, B> & ~Copyable
    consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family
}

/// Runs an effect: a generic function opens the existential, where calling it directly can trip the compiler.
/// `E.Output: ~Copyable` is spelled out: with SE-0503, `E: Effect` alone would mean a copyable output.
/// The output type is passed in, so the result doesn't depend on erasing the opened `E.Output` back to `X`.
func runEffect<E: Effect & ~Copyable, X: ~Copyable>(_ effect: consuming E, as output: X.Type, with interpreter: E.Family.Interpreter) async throws -> X
where E.Output: ~Copyable {
    let produced = try await effect.accept(interpreter)
    // the existential was an Effect with Output X, so E.Output is X
    return unsafeReinterpret(produced, as: X.self)
}

/// An effect, then the rest of the program given its output.
public enum Bind<Family: EffectFamily, X: ~Copyable, A: ~Copyable>: FreerStep, ~Copyable {
    case bind(any Effect<Family, X> & ~Copyable, next: (consuming X) -> Freer<Family, A>)

    public consuming func advance(with interpreter: Family.Interpreter) async throws -> Freer<Family, A> {
        switch consume self {
        case .bind(let effect, let next):
            let x = try await runEffect(effect, as: X.self, with: interpreter)
            return next(x)
        }
    }

    public consuming func flatMap<B: ~Copyable>(_ transform: @escaping (consuming A) -> Freer<Family, B>) -> any FreerStep<Family, B> & ~Copyable {
        switch consume self {
        case .bind(let effect, let next):
            // only closures are captured: they're copyable, unlike the effect and its output
            return Bind<Family, X, B>.bind(effect, next: { x in next(x).flatMap(transform) })
        }
    }

    /// The effect becomes a program, and the rest is translated once it's reached
    public consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        switch consume self {
        case .bind(let effect, let next):
            return translation.translate(effect).flatMap { x in next(x).translate(translation) }
        }
    }
}

/// A whole sub-program, then the rest given its result: how a `both` is followed by more program.
enum Then<Family: EffectFamily, X: ~Copyable, A: ~Copyable>: FreerStep, ~Copyable {
    case then(Freer<Family, X>, next: (consuming X) -> Freer<Family, A>)

    consuming func advance(with interpreter: Family.Interpreter) async throws -> Freer<Family, A> {
        switch consume self {
        case .then(let first, let next):
            // one level deeper for the sub-program, which itself runs as a loop
            let x = try await first.run(with: interpreter)
            return next(x)
        }
    }

    consuming func flatMap<B: ~Copyable>(_ transform: @escaping (consuming A) -> Freer<Family, B>) -> any FreerStep<Family, B> & ~Copyable {
        switch consume self {
        case .then(let first, let next):
            return Then<Family, X, B>.then(first, next: { x in next(x).flatMap(transform) })
        }
    }

    consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        switch consume self {
        case .then(let first, let next):
            return first.translate(translation).flatMap { x in next(x).translate(translation) }
        }
    }
}

/// A program, then the rest given its result and a value carried alongside: how `#do` keeps a noncopyable value
/// alive across binds. The step holds the value, so no closure has to capture it.
enum Carrying<Family: EffectFamily, X: ~Copyable, Carried: ~Copyable, A: ~Copyable>: FreerStep, ~Copyable {
    case carrying(Freer<Family, X>, Carried, next: (consuming X, consuming Carried) -> Freer<Family, A>)

    consuming func advance(with interpreter: Family.Interpreter) async throws -> Freer<Family, A> {
        switch consume self {
        case .carrying(let first, let carried, let next):
            let x = try await first.run(with: interpreter)
            return next(x, carried)
        }
    }

    consuming func flatMap<B: ~Copyable>(_ transform: @escaping (consuming A) -> Freer<Family, B>) -> any FreerStep<Family, B> & ~Copyable {
        switch consume self {
        case .carrying(let first, let carried, let next):
            return Carrying<Family, X, Carried, B>.carrying(first, carried, next: { x, carried in next(x, carried).flatMap(transform) })
        }
    }

    consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        switch consume self {
        case .carrying(let first, let carried, let next):
            return .step(Carrying<T.To, X, Carried, A>.carrying(
                first.translate(translation),
                carried,
                next: { x, carried in next(x, carried).translate(translation) }
            ))
        }
    }
}

/// Two independent programs and how to combine their results.
public enum Ap<Family: EffectFamily, X: ~Copyable, Y: ~Copyable, A: ~Copyable>: FreerBoth, ~Copyable {
    case ap(Freer<Family, X>, Freer<Family, Y>, combine: (consuming X, consuming Y) -> A)

    // In order, left then right: a concurrent interpreter is a separate piece of work
    public consuming func run(with interpreter: Family.Interpreter) async throws -> A {
        switch consume self {
        case .ap(let left, let right, let combine):
            let x = try await left.run(with: interpreter)
            let y = try await right.run(with: interpreter)
            return combine(x, y)
        }
    }

    public consuming func map<B: ~Copyable>(_ transform: @escaping (consuming A) -> B) -> any FreerBoth<Family, B> & ~Copyable {
        switch consume self {
        case .ap(let left, let right, let combine):
            return Ap<Family, X, Y, B>.ap(left, right, combine: { x, y in transform(combine(x, y)) })
        }
    }

    /// Both sides are translated and stay a `both`: independence survives translation
    public consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        switch consume self {
        case .ap(let left, let right, let combine):
            return .both(Ap<T.To, X, Y, A>.ap(left.translate(translation), right.translate(translation), combine: combine))
        }
    }
}

public extension Freer where A: ~Copyable {
    /// A program that performs one effect and returns its output
    static func perform(_ effect: consuming any Effect<Family, A> & ~Copyable) -> Freer<Family, A> {
        .step(Bind<Family, A, A>.bind(effect, next: { .pure($0) }))
    }

    /// Runs the program as a loop over its steps: each step returns the rest of the program instead of running it,
    /// so sequential binds and recursion, like a retry that calls itself, run at constant depth.
    /// Only a sub-program (a `both`'s sides, what a `Then` or a carrying step waits for) runs one level deeper.
    consuming func run(with interpreter: Family.Interpreter) async throws -> A {
        var current = consume self
        while true {
            switch consume current {
            case .pure(let a):
                return a
            case .step(let step):
                current = try await step.advance(with: interpreter)
            case .both(let both):
                current = .pure(try await both.run(with: interpreter))
            }
        }
    }

    consuming func flatMap<B: ~Copyable>(_ transform: @escaping (consuming A) -> Freer<Family, B>) -> Freer<Family, B> {
        switch consume self {
        case .pure(let a):
            return transform(a)
        case .step(let step):
            return .step(step.flatMap(transform))
        case .both(let both):
            return .step(Then<Family, A, B>.then(.both(both), next: transform))
        }
    }

    consuming func map<B: ~Copyable>(_ transform: @escaping (consuming A) -> B) -> Freer<Family, B> {
        switch consume self {
        case .pure(let a):
            return .pure(transform(a))
        case .step(let step):
            return .step(step.flatMap { .pure(transform($0)) })
        case .both(let both):
            return .both(both.map(transform))
        }
    }

    /// `flatMap`, with a value held by the program until the result is ready, then handed to `transform` with it.
    /// `#do` uses it to keep a noncopyable value alive across binds: a closure could only borrow it.
    consuming func flatMap<Carried: ~Copyable, B: ~Copyable>(
        carrying carried: consuming Carried,
        _ transform: @escaping (consuming A, consuming Carried) -> Freer<Family, B>
    ) -> Freer<Family, B> {
        switch consume self {
        case .pure(let a):
            return transform(a, carried)
        case .step(let step):
            return .step(Carrying<Family, A, Carried, B>.carrying(.step(step), carried, next: transform))
        case .both(let both):
            return .step(Carrying<Family, A, Carried, B>.carrying(.both(both), carried, next: transform))
        }
    }

    /// `map`, carrying a value like `flatMap(carrying:_:)`
    consuming func map<Carried: ~Copyable, B: ~Copyable>(
        carrying carried: consuming Carried,
        _ transform: @escaping (consuming A, consuming Carried) -> B
    ) -> Freer<Family, B> {
        flatMap(carrying: carried) { a, carried in .pure(transform(a, carried)) }
    }

    /// `flatMap(carrying:_:)` with two values, for `#do`
    consuming func flatMap<C1: ~Copyable, C2: ~Copyable, B: ~Copyable>(
        carrying c1: consuming C1, _ c2: consuming C2,
        _ transform: @escaping (consuming A, consuming C1, consuming C2) -> Freer<Family, B>
    ) -> Freer<Family, B> {
        flatMap(carrying: CarriedPair(first: c1, second: c2)) { a, pair in pair.apply(a, transform) }
    }

    /// `flatMap(carrying:_:)` with three values, for `#do`
    consuming func flatMap<C1: ~Copyable, C2: ~Copyable, C3: ~Copyable, B: ~Copyable>(
        carrying c1: consuming C1, _ c2: consuming C2, _ c3: consuming C3,
        _ transform: @escaping (consuming A, consuming C1, consuming C2, consuming C3) -> Freer<Family, B>
    ) -> Freer<Family, B> {
        flatMap(carrying: CarriedTriple(first: c1, second: c2, third: c3)) { a, triple in triple.apply(a, transform) }
    }

    /// `map(carrying:_:)` with two values, for `#do`
    consuming func map<C1: ~Copyable, C2: ~Copyable, B: ~Copyable>(
        carrying c1: consuming C1, _ c2: consuming C2,
        _ transform: @escaping (consuming A, consuming C1, consuming C2) -> B
    ) -> Freer<Family, B> {
        map(carrying: CarriedPair(first: c1, second: c2)) { a, pair in pair.apply(a, transform) }
    }

    /// `map(carrying:_:)` with three values, for `#do`
    consuming func map<C1: ~Copyable, C2: ~Copyable, C3: ~Copyable, B: ~Copyable>(
        carrying c1: consuming C1, _ c2: consuming C2, _ c3: consuming C3,
        _ transform: @escaping (consuming A, consuming C1, consuming C2, consuming C3) -> B
    ) -> Freer<Family, B> {
        map(carrying: CarriedTriple(first: c1, second: c2, third: c3)) { a, triple in triple.apply(a, transform) }
    }

    /// Replaces every effect by a program in another family, keeping the result and the structure around it:
    /// `flatMap` for effects, where `flatMap` is for results
    consuming func translate<T: Translation>(_ translation: T) -> Freer<T.To, A> where T.From == Family {
        switch consume self {
        case .pure(let a):
            return .pure(a)
        case .step(let step):
            return step.translate(translation)
        case .both(let both):
            return both.translate(translation)
        }
    }

    /// Keeps both programs visible as a `both`, instead of hiding the second behind a continuation like `flatMap`
    consuming func liftA2<B: ~Copyable, C: ~Copyable>(
        _ other: consuming Freer<Family, B>,
        _ f: @escaping (consuming A, consuming B) -> C
    ) -> Freer<Family, C> {
        .both(Ap<Family, A, B, C>.ap(self, other, combine: f))
    }

    /// Whether the program starts with two independent programs, for tests and interpreters that inspect it
    var isBoth: Bool {
        switch self {
        case .both: true
        default: false
        }
    }
}

/// Replaces each effect of `From` by a program in `To` producing the same output: `∀x. f x → Freer g x`.
/// `@EffectFamily` generates a per-family `Translation` with one method per operation, which is easier to write.
public protocol Translation<From, To> {
    associatedtype From: EffectFamily
    associatedtype To: EffectFamily

    func translate<X: ~Copyable>(_ effect: consuming any Effect<From, X> & ~Copyable) -> Freer<To, X>
}

/// `value` as a `Target`, when `Value` and `Target` are the same type but Swift can't prove it: after comparing
/// two locations, say, or to undo the type erasure of an existential that's known to hold a `Target`.
/// Checks that they are the same, then moves the value: `as!` doesn't work on noncopyable values.
/// Generated code uses it for exactly those cases; calling it with types that might differ is a bug.
public func unsafeReinterpret<Value: ~Copyable, Target: ~Copyable>(_ value: consuming Value, as target: Target.Type) -> Target {
    precondition(Value.self == Target.self, "\(Value.self) isn't \(Target.self)")
    let slot = UnsafeMutablePointer<Value>.allocate(capacity: 1)
    defer { slot.deallocate() }
    slot.initialize(to: value)
    return UnsafeMutableRawPointer(slot).assumingMemoryBound(to: Target.self).move()
}

/// Two carried values as one: noncopyable values can't go in a tuple yet
struct CarriedPair<First: ~Copyable, Second: ~Copyable>: ~Copyable {
    var first: First
    var second: Second

    /// Hands both values to `body` after `x`: a consuming method, so the fields move out without a closure capturing them
    consuming func apply<X: ~Copyable, R: ~Copyable>(_ x: consuming X, _ body: (consuming X, consuming First, consuming Second) -> R) -> R {
        body(x, first, second)
    }
}

/// Three carried values as one
struct CarriedTriple<First: ~Copyable, Second: ~Copyable, Third: ~Copyable>: ~Copyable {
    var first: First
    var second: Second
    var third: Third

    consuming func apply<X: ~Copyable, R: ~Copyable>(_ x: consuming X, _ body: (consuming X, consuming First, consuming Second, consuming Third) -> R) -> R {
        body(x, first, second, third)
    }
}
