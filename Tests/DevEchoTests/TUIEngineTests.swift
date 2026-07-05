import XCTest
@testable import dev_echo

final class TUIEngineTests: XCTestCase {
    
    func testTUIEngineInitialization() {
        let engine = TUIEngine()
        
        XCTAssertEqual(engine.currentMode, .command)
        XCTAssertTrue(engine.transcriptEntries.isEmpty)
        XCTAssertTrue(engine.llmResponses.isEmpty)
        XCTAssertFalse(engine.processingIndicator.isActive)
    }
    
    func testTUIEngineSetMode() {
        let engine = TUIEngine()
        
        engine.setMode(.transcribing)
        XCTAssertEqual(engine.currentMode, .transcribing)
        
        engine.setMode(.knowledgeBaseManagement)
        XCTAssertEqual(engine.currentMode, .knowledgeBaseManagement)
    }
    
    func testTUIEngineAppendTranscript() {
        let engine = TUIEngine()
        let entry = TranscriptEntry(source: .system, text: "Test message")
        
        engine.appendTranscript(entry: entry)
        
        XCTAssertEqual(engine.transcriptEntries.count, 1)
        XCTAssertEqual(engine.transcriptEntries.first?.text, "Test message")
    }
    
    func testTUIEngineAddSystemAudioEntry() {
        let engine = TUIEngine()
        
        engine.addSystemAudioEntry("System audio test")
        
        XCTAssertEqual(engine.transcriptEntries.count, 1)
        XCTAssertEqual(engine.transcriptEntries.first?.source, .system)
        XCTAssertEqual(engine.transcriptEntries.first?.text, "System audio test")
    }
    
    func testTUIEngineAddMicrophoneEntry() {
        let engine = TUIEngine()
        
        engine.addMicrophoneEntry("Microphone test")
        
        XCTAssertEqual(engine.transcriptEntries.count, 1)
        XCTAssertEqual(engine.transcriptEntries.first?.source, .microphone)
        XCTAssertEqual(engine.transcriptEntries.first?.text, "Microphone test")
    }
    
    func testTUIEngineAddLLMResponse() {
        let engine = TUIEngine()
        
        engine.addLLMResponse("LLM response content", model: "Llama")
        
        XCTAssertEqual(engine.llmResponses.count, 1)
        XCTAssertEqual(engine.llmResponses.first?.content, "LLM response content")
        XCTAssertEqual(engine.llmResponses.first?.model, "Llama")
    }
    
    func testTUIEngineClearTranscript() {
        let engine = TUIEngine()
        
        engine.addSystemAudioEntry("Test 1")
        engine.addMicrophoneEntry("Test 2")
        engine.addLLMResponse("Response")
        
        XCTAssertEqual(engine.transcriptEntries.count, 2)
        XCTAssertEqual(engine.llmResponses.count, 1)
        
        engine.clearTranscript()
        
        XCTAssertTrue(engine.transcriptEntries.isEmpty)
        XCTAssertTrue(engine.llmResponses.isEmpty)
    }
    
    func testTUIEngineProcessingIndicator() {
        let engine = TUIEngine()
        
        XCTAssertFalse(engine.processingIndicator.isActive)
        
        engine.showProcessingIndicator()
        XCTAssertTrue(engine.processingIndicator.isActive)
        
        engine.hideProcessingIndicator()
        XCTAssertFalse(engine.processingIndicator.isActive)
    }
    
    func testTUIEngineStatusBar() {
        let engine = TUIEngine()
        
        engine.statusBar.setAudioStatus(.active)
        engine.statusBar.setMicStatus(.active)
        
        XCTAssertEqual(engine.statusBar.audioStatus, .active)
        XCTAssertEqual(engine.statusBar.micStatus, .active)
    }
}
