import Foundation
import Testing
@testable import CopyEzzCore

@Suite struct HTTPParserTests {
    @Test func parsesRequestWithBody() throws {
        let raw = "POST /solve?x=1 HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nContent-Type: image/png\r\nContent-Length: 4\r\n\r\nabcd"
        let request = try #require(try HTTPParser.parse(Data(raw.utf8)))
        #expect(request.method == "POST")
        #expect(request.path == "/solve")
        #expect(request.header("HOST") == "127.0.0.1:8765")
        #expect(request.body == Data("abcd".utf8))
    }

    @Test func waitsForMissingBytes() throws {
        #expect(try HTTPParser.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)) == nil)
        let partialBody = "POST /solve HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        #expect(try HTTPParser.parse(Data(partialBody.utf8)) == nil)
    }

    @Test func rejectsMalformedAndOversized() {
        #expect(throws: HTTPParser.Failure.malformed) { try HTTPParser.parse(Data("NOPE\r\n\r\n".utf8)) }
        let huge = "POST /solve HTTP/1.1\r\nContent-Length: \(HTTPParser.maxBodyBytes + 1)\r\n\r\n"
        #expect(throws: HTTPParser.Failure.tooLarge) { try HTTPParser.parse(Data(huge.utf8)) }
    }

    @Test func buildsResponses() {
        let response = String(decoding: HTTPResponse.text(403, "forbidden"), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
        #expect(response.contains("Content-Length: 9\r\n"))
        #expect(response.hasSuffix("\r\n\r\nforbidden"))
    }
}

@Suite struct HTTPGuardTests {
    @Test func allowsOnlyThisLocalhost() {
        #expect(HTTPGuard.isAllowed(host: "127.0.0.1:8765", origin: nil, port: 8765))
        #expect(HTTPGuard.isAllowed(host: "localhost:8765", origin: "http://127.0.0.1:8765", port: 8765))
        #expect(!HTTPGuard.isAllowed(host: nil, origin: nil, port: 8765))
        #expect(!HTTPGuard.isAllowed(host: "evil.com:8765", origin: nil, port: 8765))  // DNS rebinding
        #expect(!HTTPGuard.isAllowed(host: "127.0.0.1:8765", origin: "https://evil.com", port: 8765))  // CSRF
        #expect(!HTTPGuard.isAllowed(host: "127.0.0.1:9999", origin: nil, port: 8765))
    }
}
