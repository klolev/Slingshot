import Testing
@testable import Slingshot

private enum Status {
    case active
    case banned
}

private struct User: Equatable {
    let name: String
    let age: Int
    let status: Status
}

private let ada = User(name: "Ada", age: 36, status: .active)
private let bob = User(name: "Bob", age: 15, status: .active)
private let eve = User(name: "Eve", age: 40, status: .banned)
private let users = [ada, bob, eve]

@Suite("Predicate")
struct PredicateTest {
    fileprivate let isAdult: Predicate<User> = { $0.age >= 18 }
    fileprivate let isActive = equals(\User.status, .active)

    @Test("equals compares the value at a key path")
    func equalsComparesTheValueAtAKeyPath() {
        #expect(users.filter(equals(\.status, .banned)) == [eve])
    }

    @Test("contramap tests what the transform gives")
    func contramapTestsWhatTheTransformGives() {
        let startsWithA: Predicate<String> = { $0.hasPrefix("A") }
        #expect(users.filter(contramap(startsWithA, \.name)) == [ada])
    }

    @Test("allOf holds when every predicate does")
    func allOfHoldsWhenEveryPredicateDoes() {
        #expect(users.filter(allOf(isAdult, isActive)) == [ada])
        #expect(users.filter(allOf([Predicate<User>]())) == users)
    }

    @Test("anyOf holds when one predicate does")
    func anyOfHoldsWhenOnePredicateDoes() {
        #expect(users.filter(anyOf(isAdult, isActive)) == users)
        #expect(users.filter(anyOf([Predicate<User>]())) == [])
    }

    @Test("noneOf holds when no predicate does")
    func noneOfHoldsWhenNoPredicateDoes() {
        #expect(users.filter(noneOf(isAdult, equals(\.name, "Bob"))) == [])
        #expect(users.filter(noneOf(equals(\.status, .banned))) == [ada, bob])
        #expect(users.filter(noneOf([Predicate<User>]())) == users)
    }

    @Test("combinators compose with && and ||")
    func combinatorsCompose() {
        #expect(users.filter(isActive && not(isAdult) || equals(\.name, "Eve")) == [bob, eve])
    }
}
