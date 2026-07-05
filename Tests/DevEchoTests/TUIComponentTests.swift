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

    // =========================================================================
    // MARK: - Reading Mode Tests (Task 18.3, 18.4, 18.6)
    // =========================================================================

    // MARK: - ApplicationMode.reading Existence & Properties (Task 18.3)

    func testReadingModeExists() {
        // Task 18.3: ApplicationMode.reading case should exist
        let mode: ApplicationMode = .reading
        XCTAssertEqual(mode, .reading)
    }

    func testReadingModeDisplayName() {
        // Task 18.3: displayName should be "Reading Mode"
        XCTAssertEqual(ApplicationMode.reading.displayName, "Reading Mode")
    }

    func testReadingModeExitHint() {
        // Task 18.3: exitHint should mention /quit to return
        let hint = ApplicationMode.reading.exitHint
        XCTAssertTrue(hint.contains("/quit"), "exitHint should mention /quit")
        XCTAssertTrue(hint.contains("return"), "exitHint should mention returning")
    }

    // MARK: - ApplicationMode.reading validCommands (Task 18.3)

    func testReadingModeValidCommandsIncludesVoice() {
        // Task 18.3: reading mode should allow /voice
        XCTAssertTrue(ApplicationMode.reading.validCommands.contains(.voice))
    }

    func testReadingModeValidCommandsContainsExactlyThreeItems() {
        // Reading mode should have exactly 3 valid commands: voice, stop, quit
        let validCommands = ApplicationMode.reading.validCommands
        XCTAssertEqual(validCommands.count, 3)
        XCTAssertEqual(validCommands, [.voice, .stop, .quit])
    }

    func testReadingModeValidCommandsIncludesStop() {
        // Task 18.3: reading mode should allow /stop (stop speech)
        XCTAssertTrue(ApplicationMode.reading.validCommands.contains(.stop))
    }

    func testReadingModeValidCommandsIncludesQuit() {
        // Task 18.3: reading mode should allow /quit (return to command mode)
        XCTAssertTrue(ApplicationMode.reading.validCommands.contains(.quit))
    }

    func testReadingModeValidCommandsExcludesChat() {
        // Task 18.3: reading mode should NOT allow /chat
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.chat))
    }

    func testReadingModeValidCommandsExcludesQuick() {
        // Task 18.3: reading mode should NOT allow /quick
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.quick))
    }

    func testReadingModeValidCommandsExcludesList() {
        // Task 18.3: reading mode should NOT allow /list
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.list))
    }

    func testReadingModeValidCommandsExcludesNew() {
        // Task 18.3: reading mode should NOT allow /new
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.new))
    }

    func testReadingModeValidCommandsExcludesManageKB() {
        // Task 18.3: reading mode should NOT allow /managekb
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.managekb))
    }

    func testReadingModeValidCommandsExcludesSave() {
        // Task 18.3: reading mode should NOT allow /save
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.save))
    }

    func testReadingModeValidCommandsExcludesMic() {
        // Task 18.3: reading mode should NOT allow /mic
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.mic))
    }

    func testReadingModeValidCommandsExcludesAdd() {
        // Task 18.3: reading mode should NOT allow /add
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.add))
    }

    func testReadingModeValidCommandsExcludesRemove() {
        // Task 18.3: reading mode should NOT allow /remove
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.remove))
    }

    func testReadingModeValidCommandsExcludesUpdate() {
        // Task 18.3: reading mode should NOT allow /update
        XCTAssertFalse(ApplicationMode.reading.validCommands.contains(.update))
    }

    // MARK: - ApplicationMode.reading isValidCommand (Task 18.3)

    func testReadingModeIsValidVoiceCommand() {
        XCTAssertTrue(ApplicationMode.reading.isValidCommand(.voice(name: "Yuna")))
        XCTAssertTrue(ApplicationMode.reading.isValidCommand(.voice(name: nil)))
    }

    func testReadingModeIsValidStopCommand() {
        XCTAssertTrue(ApplicationMode.reading.isValidCommand(.stop))
    }

    func testReadingModeIsValidQuitCommand() {
        XCTAssertTrue(ApplicationMode.reading.isValidCommand(.quit))
    }

    func testReadingModeIsNotValidChatCommand() {
        XCTAssertFalse(ApplicationMode.reading.isValidCommand(.chat(content: "test")))
    }

    func testReadingModeIsNotValidNewCommand() {
        XCTAssertFalse(ApplicationMode.reading.isValidCommand(.new))
    }

    // MARK: - ApplicationMode.reading compactCommandsHelp (Task 18.3)

    func testReadingModeCompactCommandsHelp() {
        // Task 18.3: compactCommandsHelp should contain reading mode commands (without /speed)
        let help = ApplicationMode.reading.compactCommandsHelp
        XCTAssertTrue(help.contains("/voice"), "compactCommandsHelp should contain /voice")
        XCTAssertFalse(help.contains("/speed"), "compactCommandsHelp should NOT contain /speed (removed)")
        XCTAssertTrue(help.contains("/stop"), "compactCommandsHelp should contain /stop")
        XCTAssertTrue(help.contains("/quit"), "compactCommandsHelp should contain /quit")
        // Should NOT contain commands from other modes
        XCTAssertFalse(help.contains("/chat"), "compactCommandsHelp should not contain /chat")
        XCTAssertFalse(help.contains("/new"), "compactCommandsHelp should not contain /new")
    }

    // MARK: - ApplicationMode.reading availableCommandsHelp (Task 18.3)

    func testReadingModeAvailableCommandsHelp() {
        // Task 18.3: availableCommandsHelp should describe reading mode commands (without /speed)
        let help = ApplicationMode.reading.availableCommandsHelp
        XCTAssertTrue(help.contains("/voice"), "availableCommandsHelp should mention /voice")
        XCTAssertFalse(help.contains("/speed"), "availableCommandsHelp should NOT mention /speed (removed)")
        XCTAssertTrue(help.contains("/stop"), "availableCommandsHelp should mention /stop")
        XCTAssertTrue(help.contains("/quit"), "availableCommandsHelp should mention /quit")
    }

    // MARK: - ApplicationMode.reading availableCommands for tab completion (Task 18.3)

    func testReadingModeAvailableCommands() {
        // Task 18.3: availableCommands should include reading mode command strings (without /speed)
        let commands = ApplicationMode.reading.availableCommands
        XCTAssertTrue(commands.contains { $0.hasPrefix("/voice") }, "availableCommands should include /voice")
        XCTAssertFalse(commands.contains { $0.hasPrefix("/speed") }, "availableCommands should NOT include /speed (removed)")
        XCTAssertTrue(commands.contains("/stop"), "availableCommands should include /stop")
        XCTAssertTrue(commands.contains("/quit"), "availableCommands should include /quit")
        // Should NOT include other modes' commands
        XCTAssertFalse(commands.contains("/new"), "availableCommands should not include /new")
        XCTAssertFalse(commands.contains { $0.hasPrefix("/chat") }, "availableCommands should not include /chat")
    }

    // MARK: - ApplicationMode.reading Equatable (Task 18.3)

    func testReadingModeEquatable() {
        // Ensure .reading is distinct from other modes
        XCTAssertNotEqual(ApplicationMode.reading, ApplicationMode.command)
        XCTAssertNotEqual(ApplicationMode.reading, ApplicationMode.transcribing)
        XCTAssertNotEqual(ApplicationMode.reading, ApplicationMode.knowledgeBaseManagement)
        XCTAssertEqual(ApplicationMode.reading, ApplicationMode.reading)
    }

    // MARK: - Command Mode should now include /read (Task 18.3, 18.4)

    func testCommandModeValidCommandsIncludesRead() {
        // Task 18.4: /read should be a valid command in command mode (to enter reading mode)
        XCTAssertTrue(ApplicationMode.command.validCommands.contains(.read))
    }

    func testCommandModeAvailableCommandsIncludesRead() {
        // Tab completion in command mode should include /read
        let commands = ApplicationMode.command.availableCommands
        XCTAssertTrue(commands.contains("/read"), "command mode availableCommands should include /read")
    }

    // MARK: - ApplicationModeStateMachine Reading Mode Transitions (Task 18.4)

    func testStateMachineTransitionCommandToReading() {
        // Task 18.4: .command + .read -> .reading
        var sm = ApplicationModeStateMachine(initialMode: .command)

        let result = sm.transition(with: .read)

        XCTAssertEqual(result, .success(newMode: .reading))
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineTransitionReadingToCommand() {
        // Task 18.4: .reading + .quit -> .command
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .quit)

        XCTAssertEqual(result, .success(newMode: .command))
        XCTAssertEqual(sm.currentMode, .command)
    }

    func testStateMachineReadingModeVoiceNoTransition() {
        // Task 18.4: .reading + .voice -> .noTransition (stays in reading)
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .voice(name: "Yuna"))

        XCTAssertEqual(result, .noTransition)
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineReadingModeVoiceNilNoTransition() {
        // .reading + .voice(name: nil) -> .noTransition
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .voice(name: nil))

        XCTAssertEqual(result, .noTransition)
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineReadingModeStopNoTransition() {
        // Task 18.4: .reading + .stop -> .noTransition (stays in reading)
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .stop)

        XCTAssertEqual(result, .noTransition)
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineReadingModeChatInvalid() {
        // Task 18.4: .reading + .chat -> invalidCommand (not allowed)
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .chat(content: "test"))

        if case .invalidCommand(let reason) = result {
            XCTAssertTrue(reason.contains("not available"), "Reason should mention command not available")
        } else {
            XCTFail("Expected invalidCommand result, got \(result)")
        }
        XCTAssertEqual(sm.currentMode, .reading) // Mode unchanged
    }

    func testStateMachineReadingModeNewInvalid() {
        // Task 18.4: .reading + .new -> invalidCommand (not allowed)
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .new)

        if case .invalidCommand(let reason) = result {
            XCTAssertTrue(reason.contains("not available"))
        } else {
            XCTFail("Expected invalidCommand result, got \(result)")
        }
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineReadingModeQuickInvalid() {
        // .reading + .quick -> invalidCommand
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .quick(content: "test"))

        if case .invalidCommand = result {
            // Expected
        } else {
            XCTFail("Expected invalidCommand result, got \(result)")
        }
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineReadingModeManageKBInvalid() {
        // .reading + .managekb -> invalidCommand
        var sm = ApplicationModeStateMachine(initialMode: .reading)

        let result = sm.transition(with: .managekb)

        if case .invalidCommand = result {
            // Expected
        } else {
            XCTFail("Expected invalidCommand result, got \(result)")
        }
        XCTAssertEqual(sm.currentMode, .reading)
    }

    func testStateMachineTranscribingToReadingInvalid() {
        // Task 18.4: Can't enter reading from transcribing mode
        var sm = ApplicationModeStateMachine(initialMode: .transcribing)

        let result = sm.transition(with: .read)

        if case .invalidCommand = result {
            // Expected - /read is not valid in transcribing mode
        } else {
            XCTFail("Expected invalidCommand result, got \(result)")
        }
        XCTAssertEqual(sm.currentMode, .transcribing) // Mode unchanged
    }

    func testStateMachineKBToReadingInvalid() {
        // Can't enter reading from KB management mode
        var sm = ApplicationModeStateMachine(initialMode: .knowledgeBaseManagement)

        let result = sm.transition(with: .read)

        if case .invalidCommand = result {
            // Expected - /read is not valid in KB management mode
        } else {
            XCTFail("Expected invalidCommand result, got \(result)")
        }
        XCTAssertEqual(sm.currentMode, .knowledgeBaseManagement)
    }

    // MARK: - Round Trip: command -> reading -> command (Task 18.4)

    func testStateMachineRoundTripCommandReadingCommand() {
        // Task 18.4: Full round trip preserves state correctness
        var sm = ApplicationModeStateMachine(initialMode: .command)

        // Enter reading mode
        let enterResult = sm.transition(with: .read)
        XCTAssertEqual(enterResult, .success(newMode: .reading))
        XCTAssertEqual(sm.currentMode, .reading)

        // Execute some non-mode-changing commands
        let voiceResult = sm.transition(with: .voice(name: nil))
        XCTAssertEqual(voiceResult, .noTransition)
        XCTAssertEqual(sm.currentMode, .reading)

        // Exit reading mode
        let exitResult = sm.transition(with: .quit)
        XCTAssertEqual(exitResult, .success(newMode: .command))
        XCTAssertEqual(sm.currentMode, .command)

        // Verify we're back in command mode and can enter other modes
        XCTAssertTrue(sm.canExecute(.new))
        XCTAssertTrue(sm.canExecute(.managekb))
        XCTAssertTrue(sm.canExecute(.read))
    }

    // MARK: - StateMachine canExecute for Reading Mode (Task 18.4)

    func testStateMachineCanExecuteReadFromCommand() {
        let sm = ApplicationModeStateMachine(initialMode: .command)
        XCTAssertTrue(sm.canExecute(.read))
    }

    func testStateMachineCannotExecuteReadFromTranscribing() {
        let sm = ApplicationModeStateMachine(initialMode: .transcribing)
        XCTAssertFalse(sm.canExecute(.read))
    }

    func testStateMachineCannotExecuteReadFromKB() {
        let sm = ApplicationModeStateMachine(initialMode: .knowledgeBaseManagement)
        XCTAssertFalse(sm.canExecute(.read))
    }

    func testStateMachineCanExecuteVoiceInReading() {
        let sm = ApplicationModeStateMachine(initialMode: .reading)
        XCTAssertTrue(sm.canExecute(.voice(name: "Yuna")))
        XCTAssertTrue(sm.canExecute(.voice(name: nil)))
    }

    func testStateMachineCanExecuteStopInReading() {
        let sm = ApplicationModeStateMachine(initialMode: .reading)
        XCTAssertTrue(sm.canExecute(.stop))
    }

    func testStateMachineCannotExecuteChatInReading() {
        let sm = ApplicationModeStateMachine(initialMode: .reading)
        XCTAssertFalse(sm.canExecute(.chat(content: "test")))
    }

    // MARK: - StateMachine targetMode for Reading Mode (Task 18.4)

    func testStateMachineTargetModeForReadFromCommand() {
        let sm = ApplicationModeStateMachine(initialMode: .command)
        XCTAssertEqual(sm.targetMode(for: .read), .reading)
    }

    func testStateMachineTargetModeForQuitFromReading() {
        let sm = ApplicationModeStateMachine(initialMode: .reading)
        XCTAssertEqual(sm.targetMode(for: .quit), .command)
    }

    func testStateMachineTargetModeForVoiceFromReading() {
        // /voice in reading mode does not change mode
        let sm = ApplicationModeStateMachine(initialMode: .reading)
        XCTAssertNil(sm.targetMode(for: .voice(name: "Yuna")))
    }

    // MARK: - TerminalRenderer Reading Mode Status Line (Task 18.6)

    func testBuildStatusLineForReadingMode() {
        // Task 18.6: Status line for reading mode should contain book icon and Reading
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        XCTAssertTrue(statusLine.contains("Reading"), "Status line should contain 'Reading'")
    }

    func testBuildStatusLineForReadingModeContainsBookIcon() {
        // Task 18.6: Mode indicator should show book emoji
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        // The exact emoji may vary, but should contain a reading-related icon
        // Per the task spec: "Mode indicator: Reading Mode"
        // We check for the book emoji specifically mentioned in the requirements
        XCTAssertTrue(
            statusLine.contains("\u{1F4D6}"),  // open book emoji
            "Status line should contain the book emoji for reading mode"
        )
    }

    func testBuildStatusLineForReadingModeContainsVoiceCommand() {
        // Task 18.6: Status line should mention /voice command
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        XCTAssertTrue(statusLine.contains("/voice"), "Status line should contain /voice command")
    }

    func testBuildStatusLineForReadingModeDoesNotContainSpeed() {
        // /speed is removed; status line should NOT mention /speed
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        XCTAssertFalse(statusLine.contains("/speed"), "Status line should NOT contain /speed command (removed)")
    }

    func testBuildStatusLineForReadingModeNewFormat() {
        // After /speed removal, the new format should contain preset name and /voice /stop /quit
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        XCTAssertTrue(statusLine.contains("/voice"), "New format should contain /voice")
        XCTAssertTrue(statusLine.contains("/stop"), "New format should contain /stop")
        XCTAssertTrue(statusLine.contains("/quit"), "New format should contain /quit")
        XCTAssertFalse(statusLine.contains("/speed"), "New format should NOT contain /speed")
    }

    func testBuildStatusLineForReadingModeContainsStopCommand() {
        // Task 18.6: Status line should mention /stop command
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        XCTAssertTrue(statusLine.contains("/stop"), "Status line should contain /stop command")
    }

    func testBuildStatusLineForReadingModeContainsQuitCommand() {
        // Task 18.6: Status line should mention /quit command
        let renderer = TerminalRenderer()
        let statusLine = renderer.buildStatusLine(
            mode: .reading,
            audioStatus: .inactive,
            micStatus: .inactive
        )

        XCTAssertTrue(statusLine.contains("/quit"), "Status line should contain /quit command")
    }

    // MARK: - TUIEngine Reading Mode Integration (Task 18.3)

    func testTUIEngineSetModeReading() {
        // TUIEngine should accept .reading mode
        let engine = TUIEngine()
        engine.setMode(.reading)
        XCTAssertEqual(engine.currentMode, .reading)
    }

    func testTUIEngineInitialModeIsNotReading() {
        // TUIEngine starts in command mode, not reading
        let engine = TUIEngine()
        XCTAssertNotEqual(engine.currentMode, .reading)
        XCTAssertEqual(engine.currentMode, .command)
    }
}
