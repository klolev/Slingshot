#if Macros
import Foundation
import Testing
@testable import Slingshot

@Location enum Alice {}
@Location enum Bob {}
@Location enum Carol {}

@Locations enum Pair: Alice.Includes, Bob.Includes {}
@Locations enum Everyone: Alice.Includes, Bob.Includes, Carol.Includes {}

@Effects
enum Node: Networking.Has, Embedding.Has {}

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
    func run<V>(_ body: @escaping () async throws -> V) async throws -> V {
        try await body()
    }
}

/// Alice and Bob each make a word, share it with the pair, and both build the same greeting from the two
func greeting<Effs: Choreography.Has>() -> Freer<Effs, At<Pair, String>> {
    #do { bind in
        let hello = bind(Choreography.locally(Alice.self) { _ in "hello" })
        let world = bind(Choreography.locally(Bob.self) { _ in "world" })
        let sharedHello = bind(Choreography.send(hello, to: Pair.self))
        let sharedWorld = bind(Choreography.send(world, to: Pair.self))
        return bind(Choreography.congruently(Pair.self) { pair in "\(pair(sharedHello)) \(pair(sharedWorld))" })
    }
}

func runGreeting<Me: Location>(as me: Me.Type, everyone: [String], hub: Hub) async throws -> At<Pair, String> {
    let choreography: Freer<Choreography.Family, At<Pair, String>> = greeting()
    let projected = Choreography.translate(choreography, with: Projector<Me, Node>())
    let network = InMemoryNetwork(me: Me.name, everyone: everyone, hub: hub)
    return try await projected.run(with: Node.Interpreter(networking: network, embedding: Direct()))
}

/// Alice decides, shares the decision with the pair only, and the pair branches on it in a conclave:
/// Carol takes part in the choreography but never hears about the decision
func agreement() -> Freer<Choreography.Within<Everyone>, At<Pair, String>> {
    #do { bind in
        let wantsHello = bind(Choreography.locally(Alice.self) { _ in true })
        let shared = bind(Choreography.send(wantsHello, to: Pair.self))
        return bind(Choreography.conclave(Pair.self, Pair.subset(of: Everyone.self)) {
            #do { bind in
                let choice = bind(Choreography.naked(shared))
                return choice ? "hello" : "goodbye"
            }
        })
    }
}

func runAgreement<Me: Location>(as proof: Member<Me, Everyone>, hub: Hub) async throws -> At<Pair, String> {
    let projected = Choreography.project(agreement(), as: proof, into: Node.self)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Node.Interpreter(networking: network, embedding: Direct()))
}

/// Each member of the pair makes its own word, they all get every word, and both build the same sentence:
/// the symmetric half of a protocol written once, like the peers' nonces in Hola
func exchange() -> Freer<Choreography.Within<Everyone>, At<Pair, String>> {
    #do { bind in
        let words = bind(Choreography.parallel(Pair.self) { facet in facet.location.name.uppercased() })
        let everyWord = bind(Choreography.fanIn(words, to: Pair.self))
        return bind(Choreography.congruently(Pair.self) { pair in
            let quire = pair(everyWord)
            return quire[Alice.member(of: Pair.self)] + "+" + quire[Bob.member(of: Pair.self)]
        })
    }
}

func runExchange<Me: Location>(as proof: Member<Me, Everyone>, hub: Hub) async throws -> At<Pair, String> {
    let projected = Choreography.project(exchange(), as: proof, into: Node.self)
    let network = InMemoryNetwork(me: Me.name, everyone: Everyone.members.map { $0.name }, hub: hub)
    return try await projected.run(with: Node.Interpreter(networking: network, embedding: Direct()))
}

@Suite("choreography")
struct ChoreographyTest {
    @Test("a location's name is its type's name, lowercased")
    func aLocationsNameIsItsTypesNameLowercased() {
        #expect(Alice.name == "alice")
        #expect(Pair.members.map { $0.name } == ["alice", "bob"])
    }

    @Test("a value sent to a set is held by all of it, and congruent code computes the same at each")
    func aValueSentToASetIsHeldByAllOfIt() async throws {
        let hub = Hub()
        let everyone = [Alice.name, Bob.name, Carol.name]
        async let alice = runGreeting(as: Alice.self, everyone: everyone, hub: hub)
        async let bob = runGreeting(as: Bob.self, everyone: everyone, hub: hub)
        async let carol = runGreeting(as: Carol.self, everyone: everyone, hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "hello world")
        #expect(atBob.take() == "hello world")
        // Carol isn't in the pair: she took no part and holds nothing
        #expect(!atCarol.isHeld)
    }

    @Test("a conclave branches on a value its members hold, without telling anyone else")
    func aConclaveBranchesWithoutTellingAnyoneElse() async throws {
        let hub = Hub()
        async let alice = runAgreement(as: Alice.member(of: Everyone.self), hub: hub)
        async let bob = runAgreement(as: Bob.member(of: Everyone.self), hub: hub)
        async let carol = runAgreement(as: Carol.member(of: Everyone.self), hub: hub)

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
        async let alice = runExchange(as: Alice.member(of: Everyone.self), hub: hub)
        async let bob = runExchange(as: Bob.member(of: Everyone.self), hub: hub)
        async let carol = runExchange(as: Carol.member(of: Everyone.self), hub: hub)

        let (atAlice, atBob, atCarol) = try await (alice, bob, carol)
        #expect(atAlice.take() == "ALICE+BOB")
        #expect(atBob.take() == "ALICE+BOB")
        #expect(!atCarol.isHeld)
        #expect(await hub.undelivered() == 0)
    }

    @Test("a location's reader reads its own facet")
    func aLocationsReaderReadsItsOwnFacet() {
        let facets: Faceted<Pair, String> = .init(value: "mine")
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
