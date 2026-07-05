import XCTest
@testable import dev_echo

final class CommandParserTests: XCTestCase {
    let parser = CommandParser()

    // MARK: - Command Mode Tests

    func testParseNew() {
        let result = parser.parse(input: "/new")
        XCTAssertEqual(result, .new)
    }

    func testParseManageKB() {
        let result = parser.parse(input: "/managekb")
        XCTAssertEqual(result, .managekb)
    }

    func testParseQuit() {
        let result = parser.parse(input: "/quit")
        XCTAssertEqual(result, .quit)
    }

    // MARK: - Transcribing Mode Tests

    func testParseChat() {
        let result = parser.parse(input: "/chat What is Swift?")
        XCTAssertEqual(result, .chat(content: "What is Swift?"))
    }

    func testParseQuick() {
        let result = parser.parse(input: "/quick Explain this code")
        XCTAssertEqual(result, .quick(content: "Explain this code"))
    }

    func testParseStop() {
        let result = parser.parse(input: "/stop")
        XCTAssertEqual(result, .stop)
    }

    func testParseSave() {
        let result = parser.parse(input: "/save")
        XCTAssertEqual(result, .save)
    }

    // MARK: - KB Management Mode Tests

    func testParseList() {
        let result = parser.parse(input: "/list")
        XCTAssertEqual(result, .list)
    }

    func testParseRemove() {
        let result = parser.parse(input: "/remove document.md")
        XCTAssertEqual(result, .remove(name: "document.md"))
    }

    func testParseAdd() {
        let result = parser.parse(input: "/add /path/to/file.md myfile")
        XCTAssertEqual(result, .add(fromPath: "/path/to/file.md", name: "myfile"))
    }

    func testParseUpdate() {
        let result = parser.parse(input: "/update /path/to/file.md myfile")
        XCTAssertEqual(result, .update(fromPath: "/path/to/file.md", name: "myfile"))
    }

    func testParseAddWithQuotedPath() {
        let result = parser.parse(input: "/add \"/path/with spaces/file.md\" myfile")
        XCTAssertEqual(result, .add(fromPath: "/path/with spaces/file.md", name: "myfile"))
    }

    // MARK: - Invalid Command Tests

    func testParseUnknownCommand() {
        let result = parser.parse(input: "/invalid")
        XCTAssertEqual(result, .unknown(input: "/invalid"))
    }

    func testParseNoSlash() {
        let result = parser.parse(input: "new")
        XCTAssertEqual(result, .unknown(input: "new"))
    }

    func testParseChatWithoutContent() {
        let result = parser.parse(input: "/chat")
        XCTAssertEqual(result, .unknown(input: "/chat"))
    }

    // MARK: - Reading Mode Command Parsing Tests (Task 18.1, 18.2)

    // -- /read command --

    func testParseRead() {
        // Task 18.2: /read should parse to Command.read
        let result = parser.parse(input: "/read")
        XCTAssertEqual(result, .read)
    }

    func testParseReadCaseInsensitive() {
        // Parser lowercases the command part, so /READ should also work
        let result = parser.parse(input: "/READ")
        XCTAssertEqual(result, .read)
    }

    func testParseReadWithWhitespace() {
        // Whitespace around command should be trimmed
        let result = parser.parse(input: "  /read  ")
        XCTAssertEqual(result, .read)
    }

    // -- /voice command --

    func testParseVoiceNoArgument() {
        // Task 18.2: /voice with no argument lists available voices
        let result = parser.parse(input: "/voice")
        XCTAssertEqual(result, .voice(name: nil))
    }

    func testParseVoiceWithName() {
        // Task 18.2: /voice Yuna sets voice to "Yuna"
        let result = parser.parse(input: "/voice Yuna")
        XCTAssertEqual(result, .voice(name: "Yuna"))
    }

    func testParseVoiceWithLowercaseName() {
        // Task 18.2: Voice name should be preserved as-is (case-insensitive matching is TTSEngine's job)
        let result = parser.parse(input: "/voice yuna")
        XCTAssertEqual(result, .voice(name: "yuna"))
    }

    func testParseVoiceWithMultiWordName() {
        // Voice name may contain spaces (e.g., "Samantha (Enhanced)")
        let result = parser.parse(input: "/voice Samantha Enhanced")
        XCTAssertEqual(result, .voice(name: "Samantha Enhanced"))
    }

    func testParseVoiceCaseInsensitiveCommand() {
        // Parser lowercases command part but preserves argument case
        let result = parser.parse(input: "/VOICE Yuna")
        XCTAssertEqual(result, .voice(name: "Yuna"))
    }

    // -- /speed command is REMOVED (Qwen3-TTS has no speed control) --

    func testParseSpeedReturnsUnknown() {
        // /speed is no longer a valid command; it should parse to .unknown
        let result = parser.parse(input: "/speed")
        XCTAssertEqual(result, .unknown(input: "/speed"))
    }

    func testParseSpeedWithRateReturnsUnknown() {
        // /speed 0.8 is no longer a valid command; it should parse to .unknown
        let result = parser.parse(input: "/speed 0.8")
        XCTAssertEqual(result, .unknown(input: "/speed 0.8"))
    }

    // MARK: - Command.read Equatable Tests (Task 18.1)

    func testReadCommandEquality() {
        // Command.read should be Equatable (inherits from enum Equatable conformance)
        let cmd1: Command = .read
        let cmd2: Command = .read
        XCTAssertEqual(cmd1, cmd2)
    }

    func testVoiceCommandEquality() {
        // Command.voice with same name should be equal
        XCTAssertEqual(Command.voice(name: nil), Command.voice(name: nil))
        XCTAssertEqual(Command.voice(name: "Yuna"), Command.voice(name: "Yuna"))
        XCTAssertNotEqual(Command.voice(name: nil), Command.voice(name: "Yuna"))
        XCTAssertNotEqual(Command.voice(name: "Yuna"), Command.voice(name: "Samantha"))
    }

    // MARK: - Command.commandType Tests for Reading Mode (Task 18.1)

    func testReadCommandType() {
        // Command.read should have CommandType.read
        let cmd: Command = .read
        XCTAssertEqual(cmd.commandType, .read)
    }

    func testVoiceCommandType() {
        // Command.voice should have CommandType.voice
        let cmd: Command = .voice(name: "Yuna")
        XCTAssertEqual(cmd.commandType, .voice)
    }

    func testVoiceCommandTypeNilName() {
        // Command.voice(name: nil) should also have CommandType.voice
        let cmd: Command = .voice(name: nil)
        XCTAssertEqual(cmd.commandType, .voice)
    }

    // MARK: - Command.description Tests for Reading Mode (Task 18.1)

    func testReadCommandDescription() {
        let cmd: Command = .read
        XCTAssertEqual(cmd.description, "/read")
    }

    func testVoiceCommandDescriptionNil() {
        let cmd: Command = .voice(name: nil)
        XCTAssertEqual(cmd.description, "/voice")
    }

    func testVoiceCommandDescriptionWithName() {
        let cmd: Command = .voice(name: "Yuna")
        XCTAssertEqual(cmd.description, "/voice Yuna")
    }
}
