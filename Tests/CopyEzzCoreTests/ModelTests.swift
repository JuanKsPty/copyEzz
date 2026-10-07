import CoreGraphics
import Foundation
import Testing
@testable import CopyEzzCore

@Suite struct AnswerParserTests {
    @Test(arguments: [
        ("b) TO_DATE\nConvierte texto a fecha.", "b) TO_DATE", "Convierte texto a fecha."),
        ("  b) TO_DATE  \n\n  porque sí \n", "b) TO_DATE", "porque sí"),
        ("SIN PREGUNTA", "SIN PREGUNTA", ""),
        ("   \n", "(vacío)", ""),
    ])
    func splitsAnswerAndDetail(text: String, answer: String, detail: String) {
        let result = AnswerParser.split(text)
        #expect(result.answer == answer)
        #expect(result.detail == detail)
    }
}

@Suite struct CaptureSizingTests {
    @Test func scalesLongestEdgeDown() {
        #expect(CaptureSizing.scaled(width: 3024, height: 1964) == (1568, 1018))
        #expect(CaptureSizing.scaled(width: 1964, height: 3024) == (1018, 1568))
    }

    @Test func neverScalesUp() {
        #expect(CaptureSizing.scaled(width: 1440, height: 520) == (1440, 520))
    }
}

@Suite struct EventTests {
    private func decode(_ event: ServerEvent) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: event.json()) as? [String: Any])
    }

    @Test func encodesResultsLikeThePythonServer() throws {
        let answer = SolveResult(type: .answer, id: 3, ts: 1, backend: "ollama", model: "m", answer: "b) X", detail: "d", ms: 600)
        let json = try decode(.result(answer))
        #expect(json["type"] as? String == "answer")
        #expect(json["answer"] as? String == "b) X")
        #expect(json["error"] == nil)  // los opcionales vacíos no se envían

        let error = SolveResult(type: .error, id: 4, ts: 1, backend: "api", model: "m", error: "falta key", ms: 1)
        #expect(error.title == "⚠ falta key")
        #expect(try decode(.result(error))["detail"] == nil)
    }

    @Test func encodesHelloAndThinking() throws {
        let config = BackendConfig(backend: "claude-code", model: "sonnet", backends: BackendKind.defaultModels)
        let hello = try decode(.hello(config, busy: true, results: []))
        #expect(hello["type"] as? String == "hello")
        #expect(hello["busy"] as? Bool == true)
        #expect((hello["backends"] as? [String: String])?["ollama"] == "qwen2.5vl:7b")
        #expect(try decode(.thinking(id: 7))["id"] as? Int == 7)

        let frame = String(decoding: ServerEvent.thinking(id: 7).sseFrame(), as: UTF8.self)
        #expect(frame.hasPrefix("data: {") && frame.hasSuffix("}\n\n"))
    }
}

@Suite struct HotkeyTests {
    @Test func defaultIsControlOptionCommandA() {
        #expect(Hotkey.default.display == "⌃⌥⌘A")
        #expect(Hotkey.default.matches(keyCode: 0, flags: [.maskControl, .maskAlternate, .maskCommand, .maskNumericPad]))
        #expect(!Hotkey.default.matches(keyCode: 0, flags: [.maskControl, .maskCommand]))
        #expect(!Hotkey.default.matches(keyCode: 1, flags: [.maskControl, .maskAlternate, .maskCommand]))
    }
}

@Suite struct PNGImageTests {
    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try PNGImage.encode(try #require(context.makeImage()))
    }

    @Test func readsSizeAndDownscales() throws {
        let large = try makePNG(width: 3000, height: 1000)
        #expect(PNGImage.pixelSize(large)! == (3000, 1000))
        let small = try PNGImage.downscaled(large)
        #expect(PNGImage.pixelSize(small)! == (1568, 523))
    }

    @Test func keepsSmallImagesAndRejectsNonPNG() throws {
        let png = try makePNG(width: 800, height: 600)
        #expect(try PNGImage.downscaled(png) == png)
        #expect(throws: CopyEzzError("la imagen recibida no es PNG")) { try PNGImage.downscaled(Data("hola".utf8)) }
    }

    @Test func appendsHistory() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "copyezz-test-\(UUID())/history.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = HistoryLog(url: url)
        let result = SolveResult(type: .answer, id: 1, ts: 1, backend: "b", model: "m", answer: "a", ms: 1)
        try log.append(result)
        try log.append(result)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
    }
}
