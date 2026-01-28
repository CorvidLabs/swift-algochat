import Foundation
import Testing
@testable import AlgoChat

@Suite("PSK Exchange URI Tests")
struct PSKExchangeURITests {

    private let testAddress = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAY5HFKQ"
    private let testPSK = Data(repeating: 0xAA, count: 32)

    // MARK: - Round-Trip

    @Test("Round-trip encode and parse")
    func testRoundTrip() throws {
        let uri = PSKExchangeURI(address: testAddress, psk: testPSK, label: "Alice")
        let uriString = uri.toString()
        let parsed = try PSKExchangeURI.parse(uriString)

        #expect(parsed.address == testAddress)
        #expect(parsed.psk == testPSK)
        #expect(parsed.label == "Alice")
    }

    @Test("Round-trip without label")
    func testRoundTripNoLabel() throws {
        let uri = PSKExchangeURI(address: testAddress, psk: testPSK)
        let uriString = uri.toString()
        let parsed = try PSKExchangeURI.parse(uriString)

        #expect(parsed.address == testAddress)
        #expect(parsed.psk == testPSK)
        #expect(parsed.label == nil)
    }

    // MARK: - Valid URIs

    @Test("Parse valid URI")
    func testParseValid() throws {
        let pskBase64 = testPSK.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let uriString = "algochat-psk://v1?addr=\(testAddress)&psk=\(pskBase64)&label=TestUser"
        let parsed = try PSKExchangeURI.parse(uriString)

        #expect(parsed.address == testAddress)
        #expect(parsed.psk == testPSK)
        #expect(parsed.label == "TestUser")
    }

    // MARK: - Invalid URIs

    @Test("Reject invalid scheme")
    func testRejectInvalidScheme() {
        #expect(throws: ChatError.self) {
            _ = try PSKExchangeURI.parse("https://v1?addr=\(testAddress)&psk=AAAA")
        }
    }

    @Test("Reject missing addr parameter")
    func testRejectMissingAddr() {
        let pskBase64 = testPSK.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(throws: ChatError.self) {
            _ = try PSKExchangeURI.parse("algochat-psk://v1?psk=\(pskBase64)")
        }
    }

    @Test("Reject missing psk parameter")
    func testRejectMissingPSK() {
        #expect(throws: ChatError.self) {
            _ = try PSKExchangeURI.parse("algochat-psk://v1?addr=\(testAddress)")
        }
    }

    @Test("Reject wrong PSK size")
    func testRejectWrongPSKSize() {
        let shortPSK = Data(repeating: 0xAA, count: 16).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(throws: ChatError.self) {
            _ = try PSKExchangeURI.parse("algochat-psk://v1?addr=\(testAddress)&psk=\(shortPSK)")
        }
    }

    // MARK: - URL Encoded Labels

    @Test("URL-encoded labels are handled")
    func testURLEncodedLabel() throws {
        let uri = PSKExchangeURI(address: testAddress, psk: testPSK, label: "Alice & Bob")
        let uriString = uri.toString()
        let parsed = try PSKExchangeURI.parse(uriString)

        #expect(parsed.label == "Alice & Bob")
    }

    // MARK: - Equality

    @Test("Equal URIs compare as equal")
    func testEquality() {
        let uri1 = PSKExchangeURI(address: testAddress, psk: testPSK, label: "Alice")
        let uri2 = PSKExchangeURI(address: testAddress, psk: testPSK, label: "Alice")
        #expect(uri1 == uri2)
    }
}
