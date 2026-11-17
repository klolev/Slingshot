#if Macros
import Testing
@testable import Slingshot

// The laws Freer should satisfy, checked observationally: programs hold closures and run once, so each side of a law
// is built fresh, run with the same kind of interpreter, and compared by its result and by the effects it performed.

@EffectFamily
fileprivate enum Emits {
    protocol Interpreter {
        func emit(_ value: Int) async throws -> Int
    }
}

/// Records every emitted value, in order: two programs with the same tape did the same effects
fileprivate final class Tape: Emits.Interpreter {
    var log: [Int] = []

    func emit(_ value: Int) async throws -> Int {
        log.append(value)
        return value
    }
}

/// Doubles every emitted value: a translation of Emits into itself, to check that translate is a monad morphism
fileprivate struct Doubled: Emits.Translation {
    typealias Target = Emits.Family

    func emit(_ value: Int) -> Freer<Emits.Family, Int> {
        Emits.emit(value * 2)
    }
}

/// A noncopyable value, for the strength laws: it can only be carried, never captured and consumed
fileprivate struct Token: ~Copyable {
    let value: Int
}

fileprivate func spend(_ token: consuming Token) -> Int {
    token.value
}

fileprivate typealias Program = Freer<Emits.Family, Int>

fileprivate func m() -> Program { Emits.emit(3) }
fileprivate func n() -> Program { Emits.emit(7) }
fileprivate func f(_ x: Int) -> Program { Emits.emit(x + 1) }
fileprivate func g(_ x: Int) -> Program { Emits.emit(x * 10) }
fileprivate func translated(_ program: consuming Program) -> Program { Emits.translate(program, with: Doubled()) }

/// What a program returns and which effects it performs
fileprivate struct Observation: Equatable {
    let result: Int
    let effects: [Int]
}

fileprivate func observe(_ program: consuming Program) async throws -> Observation {
    let tape = Tape()
    let result = try await program.run(with: tape)
    return Observation(result: result, effects: tape.log)
}

@Suite("freer laws")
struct FreerLawsTest {
    // MARK: Monad

    @Test("left identity: pure(a).flatMap(f) is f(a)")
    func leftIdentity() async throws {
        let lhs = try await observe(Program.pure(3).flatMap { f($0) })
        let rhs = try await observe(f(3))
        #expect(lhs == rhs)
    }

    @Test("right identity: m.flatMap(pure) is m")
    func rightIdentity() async throws {
        let lhs = try await observe(m().flatMap { .pure($0) })
        let rhs = try await observe(m())
        #expect(lhs == rhs)
    }

    @Test("associativity: m.flatMap(f).flatMap(g) is m.flatMap { f($0).flatMap(g) }")
    func associativity() async throws {
        let lhs = try await observe(m().flatMap { f($0) }.flatMap { g($0) })
        let rhs = try await observe(m().flatMap { x in f(x).flatMap { g($0) } })
        #expect(lhs == rhs)
        #expect(lhs == Observation(result: 40, effects: [3, 4, 40]))
    }

    // MARK: Functor

    @Test("map by identity changes nothing")
    func functorIdentity() async throws {
        let lhs = try await observe(m().map { $0 })
        let rhs = try await observe(m())
        #expect(lhs == rhs)
    }

    @Test("two maps are one map of the composition")
    func functorComposition() async throws {
        let lhs = try await observe(m().map { $0 + 1 }.map { $0 * 2 })
        let rhs = try await observe(m().map { ($0 + 1) * 2 })
        #expect(lhs == rhs)
    }

    @Test("map is flatMap followed by pure")
    func mapIsFlatMapThenPure() async throws {
        let lhs = try await observe(m().map { $0 + 1 })
        let rhs = try await observe(m().flatMap { .pure($0 + 1) })
        #expect(lhs == rhs)
    }

    // MARK: Applicative

    @Test("liftA2 is flatMap that carries the second program: left, then right")
    func liftA2IsFlatMapCarryingTheSecond() async throws {
        let both = m().liftA2(n()) { $0 * 100 + $1 }
        // read before #expect: its expansion could try to copy the noncopyable program
        let isBoth = both.isBoth
        #expect(isBoth)
        let lhs = try await observe(both)
        // the second program is noncopyable, so the monadic version carries it instead of capturing it
        let rhs = try await observe(m().flatMap(carrying: n()) { x, second in second.map { x * 100 + $0 } })
        #expect(lhs == rhs)
        #expect(lhs == Observation(result: 307, effects: [3, 7]))
    }

    @Test("liftA2 with pure on the left is map")
    func liftA2WithPureIsMap() async throws {
        let lhs = try await observe(Program.pure(2).liftA2(m()) { $0 + $1 })
        let rhs = try await observe(m().map { 2 + $0 })
        #expect(lhs == rhs)
    }

    @Test("a both followed by more program runs both sides, then the rest")
    func bothThenFlatMap() async throws {
        let lhs = try await observe(m().liftA2(n()) { $0 + $1 }.flatMap { g($0) })
        #expect(lhs == Observation(result: 100, effects: [3, 7, 100]))
    }

    // MARK: Strength (carrying)

    @Test("carrying over pure is applying to the value and the carried one")
    func strengthOverPure() async throws {
        let lhs = try await observe(Program.pure(3).flatMap(carrying: 4) { x, c in f(x + c) })
        let rhs = try await observe(f(7))
        #expect(lhs == rhs)
    }

    @Test("carrying a copyable value is capturing it")
    func strengthIsCaptureForCopyableValues() async throws {
        let c = 4
        let lhs = try await observe(m().flatMap(carrying: c) { x, c in f(x + c) })
        let rhs = try await observe(m().flatMap { f($0 + c) })
        #expect(lhs == rhs)
    }

    @Test("carrying then flatMap is carrying into a continuation that flatMaps")
    func strengthAssociatesWithFlatMap() async throws {
        let lhs = try await observe(m().flatMap(carrying: 4) { x, c in f(x + c) }.flatMap { g($0) })
        let rhs = try await observe(m().flatMap(carrying: 4) { x, c in f(x + c).flatMap { g($0) } })
        #expect(lhs == rhs)
    }

    @Test("carrying across a both")
    func strengthAcrossABoth() async throws {
        let lhs = try await observe(m().liftA2(n()) { $0 + $1 }.flatMap(carrying: 5) { x, c in f(x + c) })
        #expect(lhs == Observation(result: 16, effects: [3, 7, 16]))
    }

    @Test("a noncopyable value is carried across two steps and consumed once")
    func strengthCarriesNoncopyableValues() async throws {
        let program = m().flatMap(carrying: Token(value: 5)) { x, token in
            f(x).flatMap(carrying: token) { y, token in .pure(y + spend(token)) }
        }
        let observed = try await observe(program)
        #expect(observed == Observation(result: 9, effects: [3, 4]))
    }

    @Test("carrying two and three values hands them back in order")
    func strengthWithSeveralValues() async throws {
        let two = try await observe(m().flatMap(carrying: 1, 2) { x, a, b in .pure(x * 100 + a * 10 + b) })
        #expect(two == Observation(result: 312, effects: [3]))
        let three = try await observe(m().map(carrying: 1, 2, 3) { x, a, b, c in x * 1000 + a * 100 + b * 10 + c })
        #expect(three == Observation(result: 3123, effects: [3]))
    }

    // MARK: Translation is a monad morphism

    @Test("translating pure is pure")
    func translatePreservesPure() async throws {
        let lhs = try await observe(translated(.pure(3)))
        #expect(lhs == Observation(result: 3, effects: []))
    }

    @Test("translating a flatMap is flatMapping the translations")
    func translatePreservesFlatMap() async throws {
        let lhs = try await observe(translated(m().flatMap { f($0) }))
        let rhs = try await observe(translated(m()).flatMap { translated(f($0)) })
        #expect(lhs == rhs)
        #expect(lhs == Observation(result: 14, effects: [6, 14]))
    }

    @Test("translating a both is a both of the translations")
    func translatePreservesBoth() async throws {
        let program = translated(m().liftA2(n()) { $0 + $1 })
        let isBoth = program.isBoth
        #expect(isBoth)
        let lhs = try await observe(program)
        let rhs = try await observe(translated(m()).liftA2(translated(n())) { $0 + $1 })
        #expect(lhs == rhs)
    }

    @Test("translating a carrying flatMap carries into the translations")
    func translatePreservesStrength() async throws {
        let lhs = try await observe(translated(m().flatMap(carrying: 4) { x, c in f(x + c) }))
        let rhs = try await observe(translated(m()).flatMap(carrying: 4) { x, c in translated(f(x + c)) })
        #expect(lhs == rhs)
    }

    @Test("translating by a translation that changes nothing changes nothing")
    func identityTranslation() async throws {
        let lhs = try await observe(Emits.Family.hoist(m().flatMap { f($0) }, into: Emits.Family.self))
        let rhs = try await observe(m().flatMap { f($0) })
        #expect(lhs == rhs)
    }
}
#endif
