import Foundation
import Testing
@testable import Slingshot

@Suite("NonEmpty Codable")
struct NonEmpty_CodableTest {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Suite("Array")
    struct ArrayCodable {
        @Test("encodes as the underlying array")
        func encodesAsUnderlyingArray() throws {
            let data = try JSONEncoder().encode([Int].NonEmpty(first: 1, 2, 3))
            #expect(String(decoding: data, as: UTF8.self) == "[1,2,3]")
        }

        @Test("round trips")
        func roundTrips() throws {
            let decoded = try NonEmpty_CodableTest().roundTrip([Int].NonEmpty(first: 1, 2, 3))
            #expect(decoded.first == 1)
            #expect(decoded.erased == [1, 2, 3])
        }

        @Test("fails to decode an empty array")
        func failsOnEmpty() {
            #expect(throws: DecodingError.self) {
                try NonEmpty_CodableTest().decode([Int].NonEmpty.self, "[]")
            }
        }
    }

    @Suite("Set")
    struct SetCodable {
        @Test("round trips")
        func roundTrips() throws {
            let decoded = try NonEmpty_CodableTest().roundTrip(Set<Int>.NonEmpty(first: 1, 2, 3))
            #expect(decoded.erased == [1, 2, 3])
        }

        @Test("fails to decode an empty set")
        func failsOnEmpty() {
            #expect(throws: DecodingError.self) {
                try NonEmpty_CodableTest().decode(Set<Int>.NonEmpty.self, "[]")
            }
        }
    }

    @Suite("Dictionary")
    struct DictionaryCodable {
        @Test("round trips")
        func roundTrips() throws {
            let decoded = try NonEmpty_CodableTest().roundTrip([String: Int].NonEmpty(first: (key: "a", value: 1), (key: "b", value: 2)))
            #expect(decoded.erased == ["a": 1, "b": 2])
        }

        @Test("fails to decode an empty dictionary")
        func failsOnEmpty() {
            #expect(throws: DecodingError.self) {
                try NonEmpty_CodableTest().decode([String: Int].NonEmpty.self, "{}")
            }
        }
    }

    @Suite("String")
    struct StringCodable {
        @Test("encodes as the underlying string")
        func encodesAsUnderlyingString() throws {
            let data = try JSONEncoder().encode(String.NonEmpty(first: "h", "i"))
            #expect(String(decoding: data, as: UTF8.self) == #""hi""#)
        }

        @Test("round trips")
        func roundTrips() throws {
            let decoded = try NonEmpty_CodableTest().roundTrip(String.NonEmpty(first: "h", "i"))
            #expect(decoded.first == "h")
            #expect(decoded.erased == "hi")
        }

        @Test("fails to decode an empty string")
        func failsOnEmpty() {
            #expect(throws: DecodingError.self) {
                try NonEmpty_CodableTest().decode(String.NonEmpty.self, #""""#)
            }
        }
    }
}
