import Testing
@testable import Slingshot

@Suite("Ambient")
struct AmbientTest {
    struct Config: AmbientValue, Equatable {
        static let defaultValue = Config(scale: 1)
        var scale: Int
    }

    struct Name: AmbientValue, Equatable {
        static let defaultValue = Name(value: "")
        var value: String
    }

    @Suite("provide / ask")
    struct ProvideAsk {
        @Test("ask returns the provided value")
        func askReturnsTheProvidedValue() {
            let scale = Ambient.provide(Config(scale: 3)) { Ambient.ask(Config.self).scale }
            #expect(scale == 3)
        }

        @Test("ask returns the default outside provide")
        func askReturnsTheDefaultOutsideProvide() {
            #expect(Ambient.ask(Config.self) == .defaultValue)
        }

        @Test("an inner value of the same type shadows the outer one")
        func anInnerValueOfTheSameTypeShadowsTheOuterOne() {
            let scales = Ambient.provide(Config(scale: 1)) {
                let inner = Ambient.provide(Config(scale: 2)) { Ambient.ask(Config.self).scale }
                return [inner, Ambient.ask(Config.self).scale]
            }
            #expect(scales == [2, 1])
        }

        @Test("values of different types are all visible")
        func valuesOfDifferentTypesAreAllVisible() {
            let both = Ambient.provide(Config(scale: 2)) {
                Ambient.provide(Name(value: "x")) { "\(Ambient.ask(Name.self).value)\(Ambient.ask(Config.self).scale)" }
            }
            #expect(both == "x2")
        }

        @Test("local transforms the value for its body only")
        func localTransformsTheValueForItsBodyOnly() {
            let scales = Ambient.provide(Config(scale: 2)) {
                let inner = Ambient.local(Config.self, { Config(scale: $0.scale * 10) }) { Ambient.ask(Config.self).scale }
                return [inner, Ambient.ask(Config.self).scale]
            }
            #expect(scales == [20, 2])
        }
    }

    @Suite("async")
    struct Async {
        @Test("the value survives suspension")
        func theValueSurvivesSuspension() async {
            let scale = await Ambient.provide(Config(scale: 4)) {
                await Task.yield()
                return Ambient.ask(Config.self).scale
            }
            #expect(scale == 4)
        }

        @Test("child tasks of a traversal see the value")
        func childTasksOfATraversalSeeTheValue() async {
            let scaled = await Ambient.provide(Config(scale: 10)) {
                await [1, 2, 3].traverse { x in Concurrently { x * Ambient.ask(Config.self).scale } }.value
            }
            #expect(scaled == [10, 20, 30])
        }

        @Test("provide keeps the caller's actor")
        @MainActor
        func provideKeepsTheCallersActor() async {
            let counter = Counter()
            let count = await Ambient.provide(Config(scale: 1)) {
                await Task.yield()
                return counter.increment()
            }
            #expect(count == 1)
        }
    }

    @Suite("Reader")
    struct ReaderBridge {
        @Test("execute runs the reader with the ambient dependency")
        func executeRunsTheReaderWithTheAmbientDependency() {
            let reader = Reader<Config, Int> { $0.scale + 1 }
            #expect(Ambient.provide(Config(scale: 4)) { reader.execute() } == 5)
            #expect(reader.execute() == 2)
        }

        @Test("ambient turns direct-style code into a reader")
        func ambientTurnsDirectStyleCodeIntoAReader() {
            let reader = Reader<Config, Int>.ambient { Ambient.ask(Config.self).scale * 2 }
            #expect(reader.execute(with: Config(scale: 21)) == 42)
        }

        @Test("ambient readers compose with flatMap")
        func ambientReadersComposeWithFlatMap() {
            let scale = Reader<Config, Int>.ambient { Ambient.ask(Config.self).scale }
            let both = scale.flatMap { a in Reader<Config, Int> { a + $0.scale } }
            #expect(both.execute(with: Config(scale: 3)) == 6)
        }
    }
}
