import XCTest
@testable import dev_echo

final class TUIComponentTests: XCTestCase {
    
    // MARK: - StatusBarManager Tests
    
    func testStatusBarRender() {
        let statusBar = StatusBarManager(
            audioStatus: .active,
            micStatus: .active,
            currentChannel: .headphone,
            permissionStatus: PermissionStatus(screenCapture: true, microphone: true)
        )
        
        let rendered = statusBar.render()
        
        XCTAssertTrue(rendered.contains("🎧"))
        XCTAssertTrue(rendered.contains("Headphone"))
        XCTAssertTrue(rendered.contains("Audio: ON"))
        XCTAssertTrue(rendered.contains("Mic: ON"))
        XCTAssertTrue(rendered.contains("✓ Permissions"))
    }
    
    func testStatusBarInactive() {
        let statusBar = StatusBarManager(
            audioStatus: .inactive,
            micStatus: .inactive,
            currentChannel: .speaker,
            permissionStatus: PermissionStatus(screenCapture: false, microphone: false)
        )
        
        let rendered = statusBar.render()
        
        XCTAssertTrue(rendered.contains("🔈"))
        XCTAssertTrue(rendered.contains("Speaker"))
        XCTAssertTrue(rendered.contains("Audio: OFF"))
        XCTAssertTrue(rendered.contains("Mic: OFF"))
        XCTAssertTrue(rendered.contains("✗"))
    }
    
    func testStatusBarUpdate() {
        let statusBar = StatusBarManager()
        
        XCTAssertEqual(statusBar.audioStatus, .inactive)
        
        statusBar.setAudioStatus(.active)
        XCTAssertEqual(statusBar.audioStatus, .active)
        
        statusBar.setMicStatus(.active)
        XCTAssertEqual(statusBar.micStatus, .active)
        
        statusBar.setChannel(.headphone)
        XCTAssertEqual(statusBar.currentChannel, .headphone)
    }
    
    // MARK: - ProcessingIndicator Tests
    
    func testProcessingIndicatorStart() {
        var indicator = ProcessingIndicator()
        
        XCTAssertFalse(indicator.isActive)
        XCTAssertNil(indicator.startTime)
        
        indicator.start()
        
        XCTAssertTrue(indicator.isActive)
        XCTAssertNotNil(indicator.startTime)
    }
    
    func testProcessingIndicatorStop() {
        var indicator = ProcessingIndicator()
        indicator.start()
        indicator.stop()
        
        XCTAssertFalse(indicator.isActive)
        XCTAssertNil(indicator.startTime)
    }
    
    func testProcessingIndicatorRender() {
        var indicator = ProcessingIndicator(message: "Processing")
        indicator.start()
        
        let rendered = indicator.render()
        
        XCTAssertTrue(rendered.contains("Processing"))
        XCTAssertTrue(rendered.contains("for"))
    }
    
    func testProcessingIndicatorRenderWhenInactive() {
        let indicator = ProcessingIndicator()
        let rendered = indicator.render()
        
        XCTAssertEqual(rendered, "")
    }
    
    // MARK: - HeaderView Tests
    
    func testHeaderViewRender() {
        let header = HeaderView(
            version: "1.0.0",
            modelInfo: "MLX-Whisper · Ollama/Llama",
            currentDirectory: "/Users/test/project"
        )
        
        let rendered = header.render()
        
        XCTAssertTrue(rendered.contains("dev.echo"))
        XCTAssertTrue(rendered.contains("v1.0.0"))
        XCTAssertTrue(rendered.contains("MLX-Whisper"))
    }
    
    // MARK: - ApplicationMode Tests
    
    func testApplicationModeDisplayName() {
        XCTAssertEqual(ApplicationMode.command.displayName, "Command Mode")
        XCTAssertEqual(ApplicationMode.transcribing.displayName, "Transcribing Mode")
        XCTAssertEqual(ApplicationMode.knowledgeBaseManagement.displayName, "KB Management Mode")
    }
    
    func testApplicationModeValidCommands() {
        // Command mode valid commands
        XCTAssertTrue(ApplicationMode.command.validCommands.contains(.new))
        XCTAssertTrue(ApplicationMode.command.validCommands.contains(.managekb))
        XCTAssertTrue(ApplicationMode.command.validCommands.contains(.quit))
        XCTAssertFalse(ApplicationMode.command.validCommands.contains(.chat))
        
        // Transcribing mode valid commands
        XCTAssertTrue(ApplicationMode.transcribing.validCommands.contains(.chat))
        XCTAssertTrue(ApplicationMode.transcribing.validCommands.contains(.quick))
        XCTAssertTrue(ApplicationMode.transcribing.validCommands.contains(.stop))
        XCTAssertTrue(ApplicationMode.transcribing.validCommands.contains(.save))
        XCTAssertTrue(ApplicationMode.transcribing.validCommands.contains(.quit))
        XCTAssertFalse(ApplicationMode.transcribing.validCommands.contains(.new))
        
        // KB mode valid commands
        XCTAssertTrue(ApplicationMode.knowledgeBaseManagement.validCommands.contains(.list))
        XCTAssertTrue(ApplicationMode.knowledgeBaseManagement.validCommands.contains(.add))
        XCTAssertTrue(ApplicationMode.knowledgeBaseManagement.validCommands.contains(.update))
        XCTAssertTrue(ApplicationMode.knowledgeBaseManagement.validCommands.contains(.remove))
        XCTAssertTrue(ApplicationMode.knowledgeBaseManagement.validCommands.contains(.quit))
        XCTAssertFalse(ApplicationMode.knowledgeBaseManagement.validCommands.contains(.chat))
    }
    
    func testApplicationModeIsValidCommand() {
        // Command mode
        XCTAssertTrue(ApplicationMode.command.isValidCommand(.new))
        XCTAssertFalse(ApplicationMode.command.isValidCommand(.chat(content: "test")))
        
        // Transcribing mode
        XCTAssertTrue(ApplicationMode.transcribing.isValidCommand(.chat(content: "test")))
        XCTAssertFalse(ApplicationMode.transcribing.isValidCommand(.new))
        
        // KB mode
        XCTAssertTrue(ApplicationMode.knowledgeBaseManagement.isValidCommand(.list))
        XCTAssertFalse(ApplicationMode.knowledgeBaseManagement.isValidCommand(.new))
    }
    
    // MARK: - ApplicationModeStateMachine Tests
    
    func testStateMachineInitialState() {
        let sm = ApplicationModeStateMachine()
        XCTAssertEqual(sm.currentMode, .command)
        
        let smTranscribing = ApplicationModeStateMachine(initialMode: .transcribing)
        XCTAssertEqual(smTranscribing.currentMode, .transcribing)
    }
    
    func testStateMachineTransitionCommandToTranscribing() {
        var sm = ApplicationModeStateMachine(initialMode: .command)
        
        let result = sm.transition(with: .new)
        
        XCTAssertEqual(result, .success(newMode: .transcribing))
        XCTAssertEqual(sm.currentMode, .transcribing)
    }
    
    func testStateMachineTransitionCommandToKB() {
        var sm = ApplicationModeStateMachine(initialMode: .command)
        
        let result = sm.transition(with: .managekb)
        
        XCTAssertEqual(result, .success(newMode: .knowledgeBaseManagement))
        XCTAssertEqual(sm.currentMode, .knowledgeBaseManagement)
    }
    
    func testStateMachineTransitionTranscribingToCommand() {
        var sm = ApplicationModeStateMachine(initialMode: .transcribing)
        
        let result = sm.transition(with: .quit)
        
        XCTAssertEqual(result, .success(newMode: .command))
        XCTAssertEqual(sm.currentMode, .command)
    }
    
    func testStateMachineTransitionKBToCommand() {
        var sm = ApplicationModeStateMachine(initialMode: .knowledgeBaseManagement)
        
        let result = sm.transition(with: .quit)
        
        XCTAssertEqual(result, .success(newMode: .command))
        XCTAssertEqual(sm.currentMode, .command)
    }
    
    func testStateMachineInvalidCommandInMode() {
        var sm = ApplicationModeStateMachine(initialMode: .command)
        
        // /chat is not valid in command mode
        let result = sm.transition(with: .chat(content: "test"))
        
        if case .invalidCommand(let reason) = result {
            XCTAssertTrue(reason.contains("not available"))
        } else {
            XCTFail("Expected invalidCommand result")
        }
        XCTAssertEqual(sm.currentMode, .command) // Mode unchanged
    }
    
    func testStateMachineUnknownCommand() {
        var sm = ApplicationModeStateMachine(initialMode: .command)
        
        let result = sm.transition(with: .unknown(input: "invalid"))
        
        if case .invalidCommand(let reason) = result {
            XCTAssertTrue(reason.contains("Unknown command"))
        } else {
            XCTFail("Expected invalidCommand result")
        }
    }
    
    func testStateMachineNoTransitionForNonModeChangingCommand() {
        var sm = ApplicationModeStateMachine(initialMode: .transcribing)
        
        // /chat doesn't change mode
        let result = sm.transition(with: .chat(content: "test"))
        
        XCTAssertEqual(result, .noTransition)
        XCTAssertEqual(sm.currentMode, .transcribing)
    }
    
    func testStateMachineCanExecute() {
        let sm = ApplicationModeStateMachine(initialMode: .command)
        
        XCTAssertTrue(sm.canExecute(.new))
        XCTAssertTrue(sm.canExecute(.managekb))
        XCTAssertFalse(sm.canExecute(.chat(content: "test")))
        XCTAssertFalse(sm.canExecute(.unknown(input: "bad")))
    }
    
    func testStateMachineTargetMode() {
        let sm = ApplicationModeStateMachine(initialMode: .command)
        
        XCTAssertEqual(sm.targetMode(for: .new), .transcribing)
        XCTAssertEqual(sm.targetMode(for: .managekb), .knowledgeBaseManagement)
        XCTAssertNil(sm.targetMode(for: .quit)) // quit in command mode exits app, no target mode
        
        let smTranscribing = ApplicationModeStateMachine(initialMode: .transcribing)
        XCTAssertEqual(smTranscribing.targetMode(for: .quit), .command)
        XCTAssertNil(smTranscribing.targetMode(for: .chat(content: "test")))
    }
    
    // MARK: - TranscriptEntry Tests
    
    func testTranscriptEntryCreation() {
        let entry = TranscriptEntry(
            source: .system,
            text: "Hello world"
        )
        
        XCTAssertEqual(entry.source, .system)
        XCTAssertEqual(entry.text, "Hello world")
        XCTAssertFalse(entry.isLLMResponse)
    }
    
    func testTranscriptEntryFormattedTime() {
        let entry = TranscriptEntry(
            source: .microphone,
            text: "Test"
        )
        
        // Should be in HH:mm:ss format
        let time = entry.formattedTime
        XCTAssertEqual(time.count, 8) // "HH:mm:ss"
        XCTAssertTrue(time.contains(":"))
    }
    
    // MARK: - AudioSource Tests
    
    func testAudioSourceIcon() {
        XCTAssertEqual(AudioSource.system.icon, "🔊")
        XCTAssertEqual(AudioSource.microphone.icon, "🎤")
    }
    
    func testAudioSourceLabel() {
        XCTAssertEqual(AudioSource.system.label, "System Audio")
        XCTAssertEqual(AudioSource.microphone.label, "You")
    }
}
