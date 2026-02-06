//
//  AnyCodableValueTests.swift
//  MIDI2Kit
//
//  Tests for AnyCodableValue type
//

import Testing
import Foundation
@testable import MIDI2Core

// MARK: - AnyCodableValue Decoding Tests

@Suite("AnyCodableValue Tests")
struct AnyCodableValueTests {

    @Test("Decode string value")
    func decodeString() throws {
        let json = #""hello""#
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        #expect(value == .string("hello"))
        #expect(value.stringValue == "hello")
        #expect(value.intValue == nil)
    }

    @Test("Decode integer value")
    func decodeInt() throws {
        let json = "42"
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        #expect(value == .int(42))
        #expect(value.intValue == 42)
        #expect(value.doubleValue == 42.0)
        #expect(value.stringValue == nil)
    }

    @Test("Decode double value")
    func decodeDouble() throws {
        let json = "3.14"
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        #expect(value == .double(3.14))
        #expect(value.doubleValue == 3.14)
        #expect(value.intValue == nil)
    }

    @Test("Decode boolean values")
    func decodeBool() throws {
        let trueJson = "true".data(using: .utf8)!
        let falseJson = "false".data(using: .utf8)!

        let trueValue = try JSONDecoder().decode(AnyCodableValue.self, from: trueJson)
        let falseValue = try JSONDecoder().decode(AnyCodableValue.self, from: falseJson)

        #expect(trueValue == .bool(true))
        #expect(trueValue.boolValue == true)
        #expect(falseValue == .bool(false))
        #expect(falseValue.boolValue == false)
    }

    @Test("Decode null value")
    func decodeNull() throws {
        let json = "null"
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        #expect(value == .null)
        #expect(value.isNull)
        #expect(value.stringValue == nil)
    }

    @Test("Decode array of mixed types")
    func decodeArray() throws {
        let json = #"[1, "two", true, null]"#
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        let arr = try #require(value.arrayValue)
        #expect(arr.count == 4)
        #expect(arr[0] == .int(1))
        #expect(arr[1] == .string("two"))
        #expect(arr[2] == .bool(true))
        #expect(arr[3] == .null)
    }

    @Test("Decode dictionary")
    func decodeDictionary() throws {
        let json = #"{"name": "Level", "value": 100}"#
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        let dict = try #require(value.dictionaryValue)
        #expect(dict["name"] == .string("Level"))
        #expect(dict["value"] == .int(100))
    }

    @Test("Decode nested structures")
    func decodeNested() throws {
        let json = #"{"items": [{"cc": 11, "val": "high"}, {"cc": 12, "val": 64}]}"#
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        let dict = try #require(value.dictionaryValue)
        let items = try #require(dict["items"]?.arrayValue)
        #expect(items.count == 2)

        let first = try #require(items[0].dictionaryValue)
        #expect(first["cc"] == .int(11))
        #expect(first["val"] == .string("high"))
    }
}

// MARK: - Encoding Tests

@Suite("AnyCodableValue Encoding Tests")
struct AnyCodableValueEncodingTests {

    @Test("Encode and decode roundtrip")
    func encodeDecodeRoundtrip() throws {
        let values: [AnyCodableValue] = [
            .string("test"),
            .int(42),
            .double(3.14),
            .bool(true),
            .null,
            .array([.int(1), .string("two")]),
            .dictionary(["key": .int(99)])
        ]

        for original in values {
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: encoded)
            #expect(decoded == original, "Roundtrip failed for \(original)")
        }
    }
}

// MARK: - Coercion Tests

@Suite("AnyCodableValue Coercion Tests")
struct AnyCodableValueCoercionTests {

    @Test("Coerce to Int from various types")
    func coerceToInt() {
        #expect(AnyCodableValue.int(42).coercedIntValue == 42)
        #expect(AnyCodableValue.double(3.14).coercedIntValue == 3)
        #expect(AnyCodableValue.string("99").coercedIntValue == 99)
        #expect(AnyCodableValue.bool(true).coercedIntValue == 1)
        #expect(AnyCodableValue.bool(false).coercedIntValue == 0)
        #expect(AnyCodableValue.string("not-a-number").coercedIntValue == nil)
        #expect(AnyCodableValue.null.coercedIntValue == nil)
    }

    @Test("Coerce to String from various types")
    func coerceToString() {
        #expect(AnyCodableValue.string("hello").coercedStringValue == "hello")
        #expect(AnyCodableValue.int(42).coercedStringValue == "42")
        #expect(AnyCodableValue.bool(true).coercedStringValue == "true")
        #expect(AnyCodableValue.null.coercedStringValue == nil)
    }

    @Test("Double accessor converts Int to Double")
    func doubleFromInt() {
        let value = AnyCodableValue.int(100)
        #expect(value.doubleValue == 100.0)
    }
}

// MARK: - Literal Tests

@Suite("AnyCodableValue Literal Tests")
struct AnyCodableValueLiteralTests {

    @Test("String literal")
    func stringLiteral() {
        let value: AnyCodableValue = "hello"
        #expect(value == .string("hello"))
    }

    @Test("Integer literal")
    func intLiteral() {
        let value: AnyCodableValue = 42
        #expect(value == .int(42))
    }

    @Test("Float literal")
    func floatLiteral() {
        let value: AnyCodableValue = 3.14
        #expect(value == .double(3.14))
    }

    @Test("Bool literal")
    func boolLiteral() {
        let value: AnyCodableValue = true
        #expect(value == .bool(true))
    }

    @Test("Nil literal")
    func nilLiteral() {
        let value: AnyCodableValue = nil
        #expect(value == .null)
    }

    @Test("Array literal")
    func arrayLiteral() {
        let value: AnyCodableValue = [1, "two", true]
        #expect(value.arrayValue?.count == 3)
    }

    @Test("Dictionary literal")
    func dictionaryLiteral() {
        let value: AnyCodableValue = ["key": 42]
        #expect(value.dictionaryValue?["key"] == .int(42))
    }
}

// MARK: - Hashable Tests

@Suite("AnyCodableValue Hashable Tests")
struct AnyCodableValueHashableTests {

    @Test("Values can be used in sets")
    func setUsage() {
        let set: Set<AnyCodableValue> = [.int(1), .string("two"), .int(1)]
        #expect(set.count == 2)
    }

    @Test("Equal values have same hash")
    func equalHash() {
        let a = AnyCodableValue.int(42)
        let b = AnyCodableValue.int(42)
        #expect(a.hashValue == b.hashValue)
    }
}
