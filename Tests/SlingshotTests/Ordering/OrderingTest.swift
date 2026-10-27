import Testing
@testable import Slingshot

private struct Person: Equatable {
    let first: String
    let last: String
    let age: Int
    var nickname: String? = nil
}

private let ada = Person(first: "Ada", last: "Lovelace", age: 36)
private let alan = Person(first: "Alan", last: "Turing", age: 41, nickname: "Prof")
private let grace = Person(first: "Grace", last: "Hopper", age: 85, nickname: "Amazing Grace")
private let alanYoung = Person(first: "Alan", last: "Turing", age: 20)

@Suite("Ordering")
struct OrderingTest {
    @Test("natural follows Comparable")
    func naturalFollowsComparable() {
        #expect([3, 1, 2].sorted(by: Ordering.natural) == [1, 2, 3])
    }

    @Test("by orders by a key path")
    func byOrdersByAKeyPath() {
        #expect([grace, alan, ada].sorted(by: .by(\.age)) == [ada, alan, grace])
    }

    @Test("reversed flips the order")
    func reversedFlipsTheOrder() {
        #expect([ada, grace, alan].sorted(by: .by(\.age).reversed) == [grace, alan, ada])
    }

    @Test("<> only consults the right side on ties")
    func appendBreaksTies() {
        let people = [alan, grace, alanYoung, ada]
        #expect(people.sorted(by: .by(\.last) <> .by(\.age)) == [grace, ada, alanYoung, alan])
        #expect(people.sorted(by: .by(\.last) <> .by(\.age).reversed) == [grace, ada, alan, alanYoung])
    }

    @Test("zero is the identity of <>")
    func zeroIsTheIdentity() {
        let people = [alan, grace, ada]
        #expect(people.sorted(by: .zero <> .by(\.age)) == people.sorted(by: .by(\.age)))
        #expect(people.sorted(by: .by(\.age) <> .zero) == people.sorted(by: .by(\.age)))
    }

    @Test("concat chains orderings left to right")
    func concatChainsOrderings() {
        let ordering = Ordering<Person>.concat(values: [.by(\.first), .by(\.age)])
        #expect([alan, ada, alanYoung].sorted(by: ordering) == [ada, alanYoung, alan])
    }

    @Test("nilsFirst and nilsLast place nils")
    func nilsPlacement() {
        let people = [grace, ada, alan]
        #expect(people.sorted(by: .by(\.nickname, .nilsFirst(.natural))) == [ada, grace, alan])
        #expect(people.sorted(by: .by(\.nickname, .nilsLast(.natural))) == [grace, alan, ada])
    }

    @Test("min, max and sort use the ordering")
    func minMaxAndSort() {
        var people = [alan, grace, ada]
        #expect(people.min(by: .by(\.age)) == ada)
        #expect(people.max(by: .by(\.age)) == grace)
        people.sort(by: .by(\.first).reversed)
        #expect(people == [grace, alan, ada])
    }
}
