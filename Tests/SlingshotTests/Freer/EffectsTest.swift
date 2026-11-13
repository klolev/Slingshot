#if Macros
import Testing
@testable import Slingshot

@EffectFamily
fileprivate enum Keychain {
    protocol Interpreter {
        func load(_ key: String) async throws -> String?
        func store(_ value: String, for key: String) async throws
    }
}

@EffectFamily
fileprivate enum Log {
    protocol Interpreter {
        func log(_ message: String)
    }
}

@Effects
fileprivate enum App: Keychain.Has, Log.Has {}

@EffectFamily
enum Files {
    protocol Interpreter {
        func read(_ path: String) async throws -> String?
        func write(_ text: String, to path: String) async throws
    }
}

final class MemoryFiles: Files.Interpreter {
    var contents: [String: String] = [:]

    func read(_ path: String) async throws -> String? {
        contents[path]
    }

    func write(_ text: String, to path: String) async throws {
        contents[path] = text
    }
}

/// A keychain kept in files: each Keychain effect becomes a Files program
struct KeychainOnFiles: Keychain.Translation {
    typealias Target = Files.Family

    func load(_ key: String) -> Freer<Files.Family, String?> {
        Files.read("keychain/\(key)")
    }

    func store(_ value: String, for key: String) -> Freer<Files.Family, Void> {
        #do { bind in
            let _ = bind(Files.write(value, to: "keychain/\(key)"))
            return bind(Files.write(key, to: "keychain/index"))
        }
    }
}

@EffectFamily
enum Echo {
    protocol Interpreter {
        func echo<V>(_ value: V) async throws -> V
        func pair<A, B>(_ first: A, _ second: B) async -> (A, B)
        func apply<A: Numeric, B>(_ value: A, _ transform: @escaping (A) -> B) -> B
    }
}

struct Identity: Echo.Interpreter {
    func echo<V>(_ value: V) async throws -> V {
        value
    }

    func pair<A, B>(_ first: A, _ second: B) async -> (A, B) {
        (first, second)
    }

    func apply<A: Numeric, B>(_ value: A, _ transform: @escaping (A) -> B) -> B {
        transform(value)
    }
}

fileprivate final class MemoryKeychain: Keychain.Interpreter {
    var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func load(_ key: String) async throws -> String? {
        values[key]
    }

    func store(_ value: String, for key: String) async throws {
        values[key] = value
    }
}

fileprivate final class Recorder: Log.Interpreter {
    var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}

/// Works in any stack with both families, without naming one
fileprivate func cachedToken<Effs: Keychain.Has & Log.Has>() -> Freer<Effs, String?> {
    #do { bind in
        let token = bind(Keychain.load("token"))
        let _ = bind(Log.log(token == nil ? "no token" : "token found"))
        return token
    }
}

@Suite("effects")
struct EffectsTest {
    @Test("a program polymorphic in its stack runs in a concrete one")
    func aProgramPolymorphicInItsStackRunsInAConcreteOne() async throws {
        let log = Recorder()
        let program: Freer<App, String?> = cachedToken()
        let token = try await program.run(with: App.Interpreter(keychain: MemoryKeychain(["token": "abc"]), log: log))
        #expect(token == "abc")
        #expect(log.messages == ["token found"])
    }

    @Test("a family runs on its own with just its interpreter")
    func aFamilyRunsOnItsOwnWithJustItsInterpreter() async throws {
        let program: Freer<Keychain.Family, String?> = Keychain.load("token")
        #expect(try await program.run(with: MemoryKeychain(["token": "abc"])) == "abc")
    }

    @Test("dependent binds run in order")
    func dependentBindsRunInOrder() async throws {
        let keychain = MemoryKeychain()
        let program: Freer<App, String?> = #do { bind in
            let _ = bind(Keychain.store("abc", for: "token"))
            return bind(Keychain.load("token"))
        }
        let token = try await program.run(with: App.Interpreter(keychain: keychain, log: Recorder()))
        #expect(token == "abc")
    }

    @Test("independent binds stay visible as both")
    func independentBindsStayVisibleAsBoth() async throws {
        let program: Freer<App, String> = #do { bind in
            let a = bind(Keychain.load("a"))
            let b = bind(Keychain.load("b"))
            return (a ?? "-") + (b ?? "-")
        }
        guard case .both = program else {
            Issue.record("two independent binds should combine with liftA2 into a both")
            return
        }
        let result = try await program.run(with: App.Interpreter(keychain: MemoryKeychain(["a": "1"]), log: Recorder()))
        #expect(result == "1-")
    }
    
    @Test("generic requirements become generic effects")
    func genericRequirementsBecomeGenericEffects() async throws {
        let program: Freer<Echo.Family, String> = #do { bind in
            let number = bind(Echo.echo(20))
            let text = bind(Echo.echo("answer"))
            let both = bind(Echo.pair(text, number))
            let doubled = bind(Echo.apply(both.1) { $0 * 2 + 2 })
            return "\(both.0): \(doubled)"
        }
        #expect(try await program.run(with: Identity()) == "answer: 42")
    }
    
    @Test("a generic effect keeps its type arguments")
    func aGenericEffectKeepsItsTypeArguments() {
        let effect = Echo.Operations.Pair(first: 1, second: "one")
        #expect(effect.first == 1)
        #expect(effect.second == "one")
    }
    
    @Test("a translated program runs in its target")
    func aTranslatedProgramRunsInItsTarget() async throws {
        let program: Freer<Keychain.Family, Int> = #do { bind in
            let _ = bind(Keychain.store("abc", for: "token"))
            let token = bind(Keychain.load("token"))
            return token?.count ?? 0
        }
        let files = MemoryFiles()
        let onFiles = Keychain.translate(program, with: KeychainOnFiles())
        #expect(try await onFiles.run(with: files) == 3)
        #expect(files.contents == ["keychain/token": "abc", "keychain/index": "token"])
    }
    
    @Test("translation keeps independent effects as both")
    func translationKeepsIndependentEffectsAsBoth() async throws {
        let program: Freer<Keychain.Family, String> = #do { bind in
            let a = bind(Keychain.load("a"))
            let b = bind(Keychain.load("b"))
            return (a ?? "-") + (b ?? "-")
        }
        let onFiles = Keychain.translate(program, with: KeychainOnFiles())
        guard case .both = onFiles else {
            Issue.record("translating a both should give a both")
            return
        }
        let files = MemoryFiles()
        files.contents = ["keychain/b": "2"]
        #expect(try await onFiles.run(with: files) == "-2")
    }

    @Test("an effect's arguments keep their labels")
    func anEffectsArgumentsKeepTheirLabels() {
        let store = Keychain.Operations.Store(value: "abc", key: "token")
        #expect(store.value == "abc")
        #expect(store.key == "token")
    }
}
#endif
