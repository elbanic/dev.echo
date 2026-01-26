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
}
