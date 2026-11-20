#if Macros
import Foundation
import Testing
@testable import Slingshot

/// Bob's own effect: only his local code can ask for a word
@EffectFamily
enum Words {
    protocol Interpreter {
        func word() async throws -> String
    }
}

@Effects
enum AliceLocal: Words.Has, Embedding.Has {}

@Effects
enum BobLocal: Words.Has {}

@Location enum Alice {
    typealias Local = AliceLocal
}
@Location enum Bob {
    typealias Local = BobLocal
}
@Location enum Carol {}

@Locations enum Pair: Alice.Includes, Bob.Includes {}
@Locations enum Everyone: Alice.Includes, Bob.Includes, Carol.Includes {}

/// Both Alice's and Bob's local stacks have Words, so a set of them can share it
@Effects
enum SpeakerShared: Words.Has {}

@Locations enum Speakers: Alice.Includes, Bob.Includes {
    typealias Shared = SpeakerShared
}

/// Mailboxes keyed by sender and receiver, so each receive gets the next message on its own channel
actor Hub {
    private var queues: [String: [Data]] = [:]
    private var waiting: [String: CheckedContinuation<Data, Never>] = [:]

    func post(_ data: Data, from sender: String, to receiver: String) {
        let key = "\(sender)->\(receiver)"
        if let continuation = waiting.removeValue(forKey: key) {
            continuation.resume(returning: data)
        } else {
            queues[key, default: []].append(data)
        }
    }

    /// Messages sent but never received
    func undelivered() -> Int {
        queues.values.map(\.count).reduce(0, +)
    }

    func take(from sender: String, to receiver: String) async -> Data {
        let key = "\(sender)->\(receiver)"
        if var queue = queues[key], !queue.isEmpty {
            let data = queue.removeFirst()
            queues[key] = queue
            return data
        }
        return await withCheckedContinuation { waiting[key] = $0 }
    }
}

struct InMemoryNetwork: Networking.Interpreter {
    let me: String
    let everyone: [String]
    let hub: Hub

    func send<V: Codable & Sendable>(_ value: V, to location: String) async throws {
        await hub.post(try JSONEncoder().encode(value), from: me, to: location)
    }

    func receive<V: Codable & Sendable>(_ type: V.Type, from location: String) async throws -> V {
        try JSONDecoder().decode(V.self, from: await hub.take(from: location, to: me))
    }

    func broadcast<V: Codable & Sendable>(_ value: V) async throws {
        for other in everyone where other != me {
            try await send(value, to: other)
        }
    }
}

struct Direct: Embedding.Interpreter {
    func run<V: ~Copyable>(_ body: @escaping () async throws -> V) async throws -> V {
        try await body()
    }
}

struct FixedWord: Words.Interpreter {
    let value: String

    func word() async throws -> String {
        value
    }
}

// computed, so the tests don't share a global of a non-Sendable type
var aliceLocal: AliceLocal.Interpreter { .init(words: FixedWord(value: "hi"), embedding: Direct()) }
var bobLocal: BobLocal.Interpreter { .init(words: FixedWord(value: "there")) }

/// Alice and Bob each make a word (Bob asks his own Words effect for his), share it with the pair, and both build the same greeting from the two
func greeting<Effs: Choreography.Has>() -> Freer<Effs, At<Pair, String>> {
    #do { bind in
        let hello = bind(Choreography.locally(Alice.self) { _ in .pure("hello") })
        let world = bind(Choreography.locally(Bob.self) { _ in Words.word() })
        let sharedHello = bind(Choreography.send(hello, to: Pair.self))
        let sharedWorld = bind(Choreography.send(world, to: Pair.self))
        return bind(Choreography.congruently(Pair.self) { pair in "\(pair(sharedHello)) \(pair(sharedWorld))" })
    }
}

func runGreeting<Me: Location>(as me: Me.Type, local: Me.Local.Interpreter, everyone: [String], hub: Hub) async throws -> At<Pair, String> {
    let choreography: Freer<Choreography.Family, At<Pair, String>> = greeting()
    let projected = Choreography.translate(choreography, with: Projector<Me>())
    let network = InMemoryNetwork(me: Me.name, everyone: everyone, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

/// Alice decides, shares the decision with the pair only, and the pair branches on it in a conclave:
/// Carol takes part in the choreography but never hears about the decision
func agreement() -> Freer<Choreography.Within<Everyone>, At<Pair, String>> {
    #do { bind in
        let wantsHello = bind(Choreography.locally(Alice.self) { _ in .pure(true) })
        let shared = bind(Choreography.send(wantsHello, to: Pair.self))
        return bind(Choreography.conclave(Pair.self, Pair.subset(of: Everyone.self)) {
            #do { bind in
                let choice = bind(Choreography.naked(shared))
                return choice ? "hello" : "goodbye"
            }
        })
    }
}

func runAgreement<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter, hub: Hub) async throws -> At<Pair, String> {
    let projected = Choreography.project(agreement(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

/// Each member of the pair makes its own word, they all get every word, and both build the same sentence
func exchange() -> Freer<Choreography.Within<Everyone>, At<Pair, String>> {
    #do { bind in
        let words = bind(Choreography.parallel(Pair.self) { facet in .pure(facet.location.name.uppercased()) })
        let everyWord = bind(Choreography.fanIn(words, to: Pair.self))
        return bind(Choreography.congruently(Pair.self) { pair in
            let quire = pair(everyWord)
            return quire[Alice.member(of: Pair.self)] + "+" + quire[Bob.member(of: Pair.self)]
        })
    }
}

func runExchange<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter, hub: Hub) async throws -> At<Pair, String> {
    let projected = Choreography.project(exchange(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

/// Each speaker asks Words for a word, through its own interpreter, and both build the same line from them
func chorus() -> Freer<Choreography.Within<Everyone>, At<Speakers, String>> {
    #do { bind in
        let words = bind(Choreography.parallel(Speakers.self) { _ in Words.word() })
        let everyWord = bind(Choreography.fanIn(words, to: Speakers.self))
        return bind(Choreography.congruently(Speakers.self) { speakers in speakers(everyWord).all.joined(separator: " ") })
    }
}

func runChorus<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter, hub: Hub) async throws -> At<Speakers, String> {
    let projected = Choreography.project(chorus(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

/// A one-use secret, like a CPace session: reading its public part only borrows it, finishing uses it up
struct Secret: ~Copyable {
    let seed: String

    var publicPart: String {
        seed.uppercased()
    }

    consuming func finish(with answer: String) -> String {
        "\(seed)+\(answer)"
    }
}

/// Alice makes a secret, shows Bob its public part, Bob answers, and Alice finishes the secret with the answer:
/// the secret never leaves Alice, and #do carries it across both sends to the step that uses it up
func handshake() -> Freer<Choreography.Within<Everyone>, At<Alice, String>> {
    #do { bind in
        // the steps named after their location: Alice.locally is Choreography.locally(Alice.self)
        let secret = bind(Alice.locally { _ in .pure(Secret(seed: "s")) })
        let publicPart = bind(Alice.locally(borrowing: secret) { _, secret in .pure(secret.publicPart) })
        let atBob = bind(Choreography.send(publicPart, to: Bob.self))
        let answer = bind(Bob.locally { reader in .pure(reader(atBob) + "!") })
        let atAlice = bind(Choreography.send(answer, to: Alice.self))
        return bind(Alice.locally(consuming: consume secret) { reader, secret in
            .pure(secret.finish(with: reader(atAlice)))
        })
    }
}

/// Each member of the pair makes its own secret, they show each other the public parts, and each finishes its own
/// secret with all of them: the facets are noncopyable, read in place, then used up after a fanIn
func pairing() -> Freer<Choreography.Within<Everyone>, Faceted<Pair, String>> {
    #do { bind in
        let secrets = bind(Pair.parallel { facet in .pure(Secret(seed: facet.location.name)) })
        let publicParts = bind(Pair.parallel(borrowing: secrets) { _, secret in .pure(secret.publicPart) })
        let allParts = bind(Choreography.fanIn(publicParts, to: Pair.self))
        return bind(Pair.parallel(consuming: consume secrets) { facet, secret in
            // each finishes with its peer's part
            .pure(secret.finish(with: facet.others(facet(allParts)).joined(separator: ",")))
        })
    }
}

/// Alice reads her own facet of the pair's noncopyable secrets in place, and tells everyone about it:
/// no membership proof, since Pair includes Alice
func alicesPart() -> Freer<Choreography.Within<Everyone>, At<Everyone, String>> {
    #do { bind in
        let secrets = bind(Pair.parallel { facet in .pure(Secret(seed: facet.location.name)) })
        let part = bind(Alice.locally(borrowing: secrets) { _, secret in .pure(secret.publicPart) })
        let suffix = bind(Bob.constant("?"))
        let atAlice = bind(Choreography.send(suffix, to: Alice.self))
        let asked = bind(Alice.locally { reader in .pure(reader(part) + reader(atAlice)) })
        let told = bind(Choreography.send(asked, to: Everyone.self))
        return bind(Everyone.congruently { all in all(told) })
    }
}

func runAlicesPart<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter, hub: Hub) async throws -> At<Everyone, String> {
    let projected = Choreography.project(alicesPart(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

struct Refused: Error {}

/// Alice's local code throws while using up her secret: the step fails at Alice, and nobody else is involved
func refusal() -> Freer<Choreography.Within<Everyone>, At<Alice, String>> {
    #do { bind in
        let secret = bind(Choreography.locally(Alice.self) { _ in .pure(Secret(seed: "s")) })
        return bind(Choreography.locally(consuming: consume secret) { _, secret in
            if secret.seed == "s" {
                throw Refused()
            }
            return .pure(secret.finish(with: "never"))
        })
    }
}

func runRefusal<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter) async throws -> At<Alice, String> {
    let projected = Choreography.project(refusal(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: Hub())
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

func runPairing<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter, hub: Hub) async throws -> Faceted<Pair, String> {
    let projected = Choreography.project(pairing(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

func runHandshake<Me: Location>(as proof: Member<Me, Everyone>, local: Me.Local.Interpreter, hub: Hub) async throws -> At<Alice, String> {
    let projected = Choreography.project(handshake(), as: proof)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Choreography.Node<Me.Local>.Interpreter(local: local, networking: network))
}

@Suite("choreography")
struct ChoreographyTest {
    @Test("a throwing body fails its step where the value is held, and nowhere else")
    func aThrowingBodyFailsItsStep() async throws {
        await #expect(throws: Refused.self) {
            _ = try await runRefusal(as: Alice.member(of: Everyone.self), local: aliceLocal)
        }
        let atBob = try await runRefusal(as: Bob.member(of: Everyone.self), local: bobLocal)
        #expect(!atBob.isHeld)
    }

    @Test("noncopyable facets are read in place at each member, then used up after a fanIn")
    func noncopyableFacetsAreReadThenUsedUp() async throws {
        let hub = Hub()
        async let alice = runPairing(as: Alice.member(of: Everyone.self), local: aliceLocal, hub: hub)
        async let bob = runPairing(as: Bob.member(of: Everyone.self), local: bobLocal, hub: hub)
        async let carol = runPairing(as: Carol.member(of: Everyone.self), local: Direct(), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(Alice.Reader(_unchecked: ())(atAlice) == "alice+BOB")
        #expect(Bob.Reader(_unchecked: ())(atBob) == "bob+ALICE")
        #expect(!atCarol.isHeld)
        #expect(await hub.undelivered() == 0)
    }

    @Test("a noncopyable value stays at its location, is read in place, and is used up after later sends")
    func aNoncopyableValueIsReadThenUsedUp() async throws {
        let hub = Hub()
        async let alice = runHandshake(as: Alice.member(of: Everyone.self), local: aliceLocal, hub: hub)
        async let bob = runHandshake(as: Bob.member(of: Everyone.self), local: bobLocal, hub: hub)
        async let carol = runHandshake(as: Carol.member(of: Everyone.self), local: Direct(), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "s+S!")
        #expect(!atBob.isHeld)
        #expect(!atCarol.isHeld)
        #expect(await hub.undelivered() == 0)
    }

    @Test("a location reads its own noncopyable facet in place, without a membership proof")
    func aLocationReadsItsOwnFacetInPlace() async throws {
        let hub = Hub()
        async let alice = runAlicesPart(as: Alice.member(of: Everyone.self), local: aliceLocal, hub: hub)
        async let bob = runAlicesPart(as: Bob.member(of: Everyone.self), local: bobLocal, hub: hub)
        async let carol = runAlicesPart(as: Carol.member(of: Everyone.self), local: Direct(), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "ALICE?")
        #expect(atBob.take() == "ALICE?")
        #expect(atCarol.take() == "ALICE?")
        #expect(await hub.undelivered() == 0)
    }

    @Test("a location's name is its type's name, lowercased")
    func aLocationsNameIsItsTypesNameLowercased() {
        #expect(Alice.name == "alice")
        #expect(Pair.members.map { $0.name } == ["alice", "bob"])
    }

    @Test("a value sent to a set is held by all of it, and congruent code computes the same at each")
    func aValueSentToASetIsHeldByAllOfIt() async throws {
        let hub = Hub()
        let everyone = [Alice.name, Bob.name, Carol.name]
        async let alice = runGreeting(as: Alice.self, local: aliceLocal, everyone: everyone, hub: hub)
        async let bob = runGreeting(as: Bob.self, local: BobLocal.Interpreter(words: FixedWord(value: "world")), everyone: everyone, hub: hub)
        async let carol = runGreeting(as: Carol.self, local: Direct(), everyone: everyone, hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "hello world")
        #expect(atBob.take() == "hello world")
        // Carol isn't in the pair: she took no part and holds nothing
        #expect(!atCarol.isHeld)
    }

    @Test("a conclave branches on a value its members hold, without telling anyone else")
    func aConclaveBranchesWithoutTellingAnyoneElse() async throws {
        let hub = Hub()
        async let alice = runAgreement(as: Alice.member(of: Everyone.self), local: aliceLocal, hub: hub)
        async let bob = runAgreement(as: Bob.member(of: Everyone.self), local: bobLocal, hub: hub)
        async let carol = runAgreement(as: Carol.member(of: Everyone.self), local: Direct(), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "hello")
        #expect(atBob.take() == "hello")
        #expect(!atCarol.isHeld)
        // A branch would have broadcast the decision to Carol too; the conclave sent her nothing
        #expect(await hub.undelivered() == 0)
    }

    @Test("parallel makes a facet per member, and fanIn gathers them at every receiver")
    func parallelAndFanIn() async throws {
        let hub = Hub()
        async let alice = runExchange(as: Alice.member(of: Everyone.self), local: aliceLocal, hub: hub)
        async let bob = runExchange(as: Bob.member(of: Everyone.self), local: bobLocal, hub: hub)
        async let carol = runExchange(as: Carol.member(of: Everyone.self), local: Direct(), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "ALICE+BOB")
        #expect(atBob.take() == "ALICE+BOB")
        #expect(!atCarol.isHeld)
        #expect(await hub.undelivered() == 0)
    }

    @Test("a set's shared effects run at each member, with its own local interpreter")
    func aSetsSharedEffectsRunAtEachMember() async throws {
        let hub = Hub()
        async let alice = runChorus(as: Alice.member(of: Everyone.self), local: aliceLocal, hub: hub)
        async let bob = runChorus(as: Bob.member(of: Everyone.self), local: bobLocal, hub: hub)
        async let carol = runChorus(as: Carol.member(of: Everyone.self), local: Direct(), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "hi there")
        #expect(atBob.take() == "hi there")
        #expect(!atCarol.isHeld)
        #expect(await hub.undelivered() == 0)
    }

    @Test("a family's program hoists into any stack that has it")
    func aFamilysProgramHoists() async throws {
        let word: Freer<Words.Family, String> = Words.word()
        #expect(try await Words.Family.hoist(word, into: AliceLocal.self).run(with: aliceLocal) == "hi")
    }

    @Test("a stack's program hoists into any stack that has all its families")
    func aStacksProgramHoists() async throws {
        let word: Freer<SpeakerShared, String> = Words.word()
        #expect(try await SpeakerShared.hoist(word, into: BobLocal.self).run(with: bobLocal) == "there")
    }

    @Test("faceted makes each member's own value its facet")
    func facetedMakesEachMembersValueItsFacet() {
        // as projected at Alice: she holds her value, not Bob's
        let atAlice = Pair.faceted(alice: At<Alice, String>(value: "a"), bob: .absent)
        #expect(Alice.Reader(_unchecked: ())(atAlice) == "a")

        // as projected at Bob
        let atBob = Pair.faceted(alice: .absent, bob: At<Bob, String>(value: "b"))
        #expect(Bob.Reader(_unchecked: ())(atBob) == "b")

        // as projected at Carol, who isn't in the pair
        let atCarol = Pair.faceted(alice: At<Alice, String>.absent, bob: .absent)
        #expect(!atCarol.isHeld)
    }

    @Test("faceted makes each member's own noncopyable value its facet")
    func facetedTakesNoncopyableValues() {
        let atAlice = Pair.faceted(alice: At<Alice, Secret>(value: Secret(seed: "a")), bob: .absent)
        let secret = Alice.Reader(_unchecked: ())(atAlice)
        #expect(secret.seed == "a")
    }

    @Test("faceted makes each member's constant its facet")
    func facetedMakesEachMembersConstantItsFacet() async throws {
        // a program runs once, so each projection gets its own
        func roles() -> Freer<Choreography.Family, Faceted<Pair, String>> {
            Pair.faceted(alice: "first", bob: "second")
        }
        let hub = Hub()

        let atAlice = try await Choreography.translate(roles(), with: Projector<Alice>())
            .run(with: .init(local: aliceLocal, networking: InMemoryNetwork(me: Alice.name, everyone: [], hub: hub)))
        #expect(Alice.Reader(_unchecked: ())(atAlice) == "first")

        let atBob = try await Choreography.translate(roles(), with: Projector<Bob>())
            .run(with: .init(local: bobLocal, networking: InMemoryNetwork(me: Bob.name, everyone: [], hub: hub)))
        #expect(Bob.Reader(_unchecked: ())(atBob) == "second")
    }

    @Test("a location's reader reads its own facet")
    func aLocationsReaderReadsItsOwnFacet() {
        let facets: Faceted<Pair, String> = .init(value: "mine", at: Bob.self)
        #expect(Bob.Reader(_unchecked: ())(facets) == "mine")
    }

    @Test("a location's reader reads values held by a set that includes it")
    func aLocationsReaderReadsValuesHeldByASetThatIncludesIt() {
        let held: At<Pair, Int> = .init(value: 42)
        let mine: At<Alice, Int> = .init(value: 1)
        let reader = Alice.Reader(_unchecked: ())
        #expect(reader(held) == 42)
        #expect(reader(mine) == 1)
    }

    @Test("a membership proof reads for its location")
    func aMembershipProofReadsForItsLocation() {
        let held: At<Pair, Int> = .init(value: 42)
        let proof = Bob.member(of: Pair.self)
        #expect(proof.read(held, with: Bob.Reader(_unchecked: ())) == 42)
    }
}
#endif
