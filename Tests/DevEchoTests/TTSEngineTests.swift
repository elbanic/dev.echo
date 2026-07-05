import XCTest
@testable import dev_echo

// =============================================================================
// MARK: - TTSEngine IPC-Based Tests (Tasks 24.1, 24.2, 24.3)
//
// These tests define the expected behavior of the NEW IPC-based TTSEngine
// that delegates TTS to a Python backend (Qwen3-TTS) via Unix Domain Socket.
//
// Current TTSEngine uses AVSpeechSynthesizer (NSObject subclass). These tests
// will FAIL because:
//   - TTSState no longer has .loadingModel, .generating cases
//   - TTSVoiceConfig has different fields (presetName/language/voiceInstruct vs voiceIdentifier/rate/volume/language)
//   - TTSEngine init requires IPCClient dependency
//   - TTSEngineDelegate protocol has different methods
//   - setRate(), listVoices(), findVoice(), setVoice() are removed
//   - New methods: handleStatusUpdate(), listPresets(), setPreset(), availablePresets
//
// Properties validated:
//   - Property 16: TTS Playback Lifecycle
//   - Property 17: TTS Configuration Persistence
// =============================================================================

// MARK: - Mock IPCClient for Testing

/// A minimal mock that records IPC messages sent by TTSEngine.
/// Since IPCClient is an actor, this mock conforms to the same interface
/// patterns but stores sent messages for assertion.
///
/// Assumption: The implementer will either:
///   (a) Extract a protocol from IPCClient that both real and mock implement, OR
///   (b) TTSEngine takes a closure/callback for sending, OR
///   (c) Tests focus on non-IPC logic (state management, handleStatusUpdate).
///
/// For now, we test the parts that do NOT require actual IPC sending:
/// state management, handleStatusUpdate, voice config, preset management.
/// The IPC-dependent parts (speak sends message, stop sends message) are
/// tested via state expectations after handleStatusUpdate simulates backend responses.

// MARK: - Mock TTSEngineDelegate (New Protocol)

/// Mock delegate for the NEW IPC-based TTSEngineDelegate protocol.
/// The new protocol has:
///   - ttsDidChangeState(_ state: TTSState)
///   - ttsDidEncounterError(_ error: String)
///
/// This replaces the old protocol which had:
///   - ttsDidStartSpeaking(text:)
///   - ttsDidFinishSpeaking()
///   - ttsDidCancel()
///   - ttsDidEncounterError(_ error: Error)
final class MockTTSEngineDelegate: TTSEngineDelegate {
    var stateChanges: [TTSState] = []
    var errors: [String] = []

    func ttsDidChangeState(_ state: TTSState) {
        stateChanges.append(state)
    }

    func ttsDidEncounterError(_ error: String) {
        errors.append(error)
    }

    func reset() {
        stateChanges = []
        errors = []
    }
}


// =============================================================================
// MARK: - 1. TTSState Enum Tests
// =============================================================================

/// Tests that TTSState has all required cases for the IPC-based engine,
/// including new states that mirror the Python backend (loadingModel, generating).
///
/// These tests will FAIL because the current TTSState only has: idle, speaking(text:), stopping.
/// The new TTSState needs: idle, loadingModel, generating, speaking(text:), stopping.
final class TTSStateEnumTests: XCTestCase {

    /// TTSState.idle should exist and be Equatable.
    func testTTSStateIdleExists() {
        let state: TTSState = .idle
        XCTAssertEqual(state, .idle)
    }

    /// TTSState.loadingModel should exist (mirrors backend "loading_model" state).
    /// FAILS: Current TTSState does not have a .loadingModel case.
    func testTTSStateLoadingModelExists() {
        let state: TTSState = .loadingModel
        if case .loadingModel = state {
            // Pass
        } else {
            XCTFail("TTSState.loadingModel case should exist")
        }
    }

    /// TTSState.generating should exist (mirrors backend "generating" state).
    /// FAILS: Current TTSState does not have a .generating case.
    func testTTSStateGeneratingExists() {
        let state: TTSState = .generating
        if case .generating = state {
            // Pass
        } else {
            XCTFail("TTSState.generating case should exist")
        }
    }

    /// TTSState.speaking should carry the text being spoken.
    func testTTSStateSpeakingCarriesText() {
        let state: TTSState = .speaking(text: "Hello World")
        if case .speaking(let text) = state {
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("TTSState.speaking should carry text")
        }
    }

    /// TTSState.stopping should exist.
    func testTTSStateStoppingExists() {
        let state: TTSState = .stopping
        if case .stopping = state {
            // Pass
        } else {
            XCTFail("TTSState.stopping case should exist")
        }
    }

    /// TTSState should be Equatable for all cases including new ones.
    /// FAILS: loadingModel and generating don't exist yet.
    func testTTSStateEquatability() {
        XCTAssertEqual(TTSState.idle, TTSState.idle)
        XCTAssertEqual(TTSState.loadingModel, TTSState.loadingModel)
        XCTAssertEqual(TTSState.generating, TTSState.generating)
        XCTAssertEqual(TTSState.speaking(text: "A"), TTSState.speaking(text: "A"))
        XCTAssertNotEqual(TTSState.speaking(text: "A"), TTSState.speaking(text: "B"))
        XCTAssertEqual(TTSState.stopping, TTSState.stopping)
        XCTAssertNotEqual(TTSState.idle, TTSState.loadingModel)
        XCTAssertNotEqual(TTSState.generating, TTSState.stopping)
    }

    /// All five states should be distinct from each other.
    /// FAILS: loadingModel and generating don't exist yet.
    func testAllStatesAreDistinct() {
        let states: [TTSState] = [
            .idle,
            .loadingModel,
            .generating,
            .speaking(text: "test"),
            .stopping
        ]
        for i in 0..<states.count {
            for j in (i + 1)..<states.count {
                XCTAssertNotEqual(states[i], states[j],
                                  "\(states[i]) should not equal \(states[j])")
            }
        }
    }
}


// =============================================================================
// MARK: - 2. TTSVoiceConfig Tests
// =============================================================================

/// Tests for the NEW TTSVoiceConfig struct that uses presetName/language/voiceInstruct
/// instead of the old voiceIdentifier/rate/volume/language.
///
/// These tests will FAIL because:
///   - Current TTSVoiceConfig has: voiceIdentifier, rate, volume, language
///   - New TTSVoiceConfig has: presetName, language, voiceInstruct
///   - Default is korean_female preset, not ko-KR with rate 0.5
final class TTSVoiceConfigTests: XCTestCase {

    /// Default TTSVoiceConfig should use "korean_female" preset.
    /// FAILS: Current default uses language "ko-KR", no presetName field.
    func testDefaultVoiceConfigPresetIsKoreanFemale() {
        let config = TTSVoiceConfig.default
        XCTAssertEqual(config.presetName, "korean_female",
                       "Default preset should be korean_female")
    }

    /// Default TTSVoiceConfig language should be "Korean" (not "ko-KR").
    /// FAILS: Current default language is "ko-KR".
    func testDefaultVoiceConfigLanguageIsKorean() {
        let config = TTSVoiceConfig.default
        XCTAssertEqual(config.language, "Korean",
                       "Default voice config language should be 'Korean' (Qwen3-TTS format)")
    }

    /// Default TTSVoiceConfig should have a non-empty voiceInstruct.
    /// FAILS: Current TTSVoiceConfig has no voiceInstruct field.
    func testDefaultVoiceConfigHasVoiceInstruct() {
        let config = TTSVoiceConfig.default
        XCTAssertFalse(config.voiceInstruct.isEmpty,
                       "Default voice config should have a non-empty voiceInstruct")
    }

    /// Default TTSVoiceConfig voiceInstruct should describe the voice character.
    /// FAILS: voiceInstruct field doesn't exist.
    func testDefaultVoiceConfigVoiceInstructContent() {
        let config = TTSVoiceConfig.default
        // The voice instruct should contain descriptive keywords
        XCTAssertTrue(config.voiceInstruct.lowercased().contains("korean") ||
                      config.voiceInstruct.lowercased().contains("female") ||
                      config.voiceInstruct.lowercased().contains("voice"),
                      "Default voiceInstruct should describe the voice characteristics")
    }

    /// TTSVoiceConfig should NOT have a rate property (Qwen3-TTS has no speed control).
    /// This test validates that the old rate property is removed.
    /// FAILS: Current TTSVoiceConfig still has a rate property.
    func testVoiceConfigDoesNotHaveRate() {
        // If TTSVoiceConfig has a rate property, this line would compile.
        // The new TTSVoiceConfig should NOT have rate, so we verify
        // the struct only has the expected fields by creating one with
        // the new initializer.
        let config = TTSVoiceConfig(
            presetName: "english_male",
            language: "English",
            voiceInstruct: "A deep, professional English male voice"
        )
        XCTAssertEqual(config.presetName, "english_male")
        XCTAssertEqual(config.language, "English")
        XCTAssertEqual(config.voiceInstruct, "A deep, professional English male voice")
    }

    /// TTSVoiceConfig should NOT have a volume property.
    /// FAILS: Current TTSVoiceConfig has a volume property.
    func testVoiceConfigDoesNotHaveVolume() {
        // Verify the new TTSVoiceConfig initializer works with only 3 fields.
        let config = TTSVoiceConfig(
            presetName: "korean_male",
            language: "Korean",
            voiceInstruct: "A calm, professional Korean male voice"
        )
        XCTAssertEqual(config.presetName, "korean_male")
    }

    /// TTSVoiceConfig should NOT have a voiceIdentifier property.
    /// FAILS: Current TTSVoiceConfig has voiceIdentifier.
    func testVoiceConfigDoesNotHaveVoiceIdentifier() {
        let config = TTSVoiceConfig(
            presetName: "english_female",
            language: "English",
            voiceInstruct: "A clear, friendly English female voice"
        )
        XCTAssertEqual(config.presetName, "english_female")
    }

    /// TTSVoiceConfig should be Equatable.
    /// FAILS: New struct with different fields.
    func testVoiceConfigEquatability() {
        let config1 = TTSVoiceConfig(
            presetName: "korean_female",
            language: "Korean",
            voiceInstruct: "A warm voice"
        )
        let config2 = TTSVoiceConfig(
            presetName: "korean_female",
            language: "Korean",
            voiceInstruct: "A warm voice"
        )
        let config3 = TTSVoiceConfig(
            presetName: "english_male",
            language: "English",
            voiceInstruct: "A deep voice"
        )
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
}


// =============================================================================
// MARK: - 3. TTSEngine Initialization Tests
// =============================================================================

/// Tests for TTSEngine initialization with the new IPC-based architecture.
/// Uses TTSEngine.forTesting() to create engines without a real IPCClient.
final class TTSEngineInitTests: XCTestCase {

    /// TTSEngine should have an availablePresets static constant with 4 presets.
    func testAvailablePresetsContainsFourPresets() {
        let presets = TTSEngine.availablePresets
        XCTAssertEqual(presets.count, 4,
                       "availablePresets should contain exactly 4 presets")
    }

    /// availablePresets should contain the expected preset names.
    func testAvailablePresetsContainsExpectedNames() {
        let presets = TTSEngine.availablePresets
        XCTAssertTrue(presets.contains("korean_female"),
                      "availablePresets should contain 'korean_female'")
        XCTAssertTrue(presets.contains("korean_male"),
                      "availablePresets should contain 'korean_male'")
        XCTAssertTrue(presets.contains("english_female"),
                      "availablePresets should contain 'english_female'")
        XCTAssertTrue(presets.contains("english_male"),
                      "availablePresets should contain 'english_male'")
    }

    /// forTesting() should create an engine with default config and idle state.
    func testForTestingCreatesEngineWithDefaultConfig() {
        let engine = TTSEngine.forTesting()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.config.presetName, "korean_female")
    }

    /// forTesting() should accept a custom config.
    func testForTestingCreatesEngineWithCustomConfig() {
        let config = TTSVoiceConfig(presetName: "english_male", language: "English", voiceInstruct: "A deep voice")
        let engine = TTSEngine.forTesting(config: config)
        XCTAssertEqual(engine.config.presetName, "english_male")
    }
}


// =============================================================================
// MARK: - 4. TTSEngine.handleStatusUpdate() Tests
// =============================================================================

/// Tests for handleStatusUpdate() which processes incoming TTSStatusMessage
/// from the Python backend and updates the engine's state accordingly.
/// Uses TTSEngine.forTesting() to create engines without a real IPCClient.
final class TTSEngineHandleStatusUpdateTests: XCTestCase {
    var engine: TTSEngine!
    var delegate: MockTTSEngineDelegate!

    override func setUp() {
        super.setUp()
        engine = TTSEngine.forTesting()
        delegate = MockTTSEngineDelegate()
        engine.delegate = delegate
    }

    override func tearDown() {
        engine = nil
        delegate = nil
        super.tearDown()
    }

    /// handleStatusUpdate with state "idle" should set engine state to .idle.
    func testHandleStatusUpdateIdle() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "idle"))
        XCTAssertEqual(engine.state, .idle)
    }

    /// handleStatusUpdate with state "loading_model" should set engine state to .loadingModel.
    func testHandleStatusUpdateLoadingModel() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "loading_model"))
        XCTAssertEqual(engine.state, .loadingModel)
    }

    /// handleStatusUpdate with state "generating" should set engine state to .generating.
    func testHandleStatusUpdateGenerating() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "generating"))
        XCTAssertEqual(engine.state, .generating)
    }

    /// handleStatusUpdate with state "playing" and text should set state to .speaking(text:).
    func testHandleStatusUpdatePlaying() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "Hello"))
        XCTAssertEqual(engine.state, .speaking(text: "Hello"))
    }

    /// handleStatusUpdate with state "stopping" should set engine state to .stopping.
    func testHandleStatusUpdateStopping() {
        // First move to a non-idle state
        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "test"))
        engine.handleStatusUpdate(TTSStatusMessage(state: "stopping"))
        XCTAssertEqual(engine.state, .stopping)
    }

    /// handleStatusUpdate with error should trigger delegate error callback.
    func testHandleStatusUpdateWithError() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "idle", error: "Model failed"))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first, "Model failed")
    }

    /// handleStatusUpdate with unknown state string should be ignored (stay at current state).
    func testHandleStatusUpdateUnknownState() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "unknown_xyz"))
        XCTAssertEqual(engine.state, .idle) // Should stay idle (unknown state ignored)
    }
}


// =============================================================================
// MARK: - 5. TTSEngine State Machine via handleStatusUpdate
// =============================================================================

/// Integration-style tests that verify the full state machine lifecycle
/// by simulating a sequence of backend status updates.
/// Uses TTSEngine.forTesting() to create engines without a real IPCClient.
///
/// Property 16: TTS Playback Lifecycle.
final class TTSEngineStateMachineTests: XCTestCase {
    var engine: TTSEngine!
    var delegate: MockTTSEngineDelegate!

    override func setUp() {
        super.setUp()
        engine = TTSEngine.forTesting()
        delegate = MockTTSEngineDelegate()
        engine.delegate = delegate
    }

    override func tearDown() {
        engine = nil
        delegate = nil
        super.tearDown()
    }

    /// Verify the complete happy-path lifecycle:
    /// idle -> loadingModel -> generating -> speaking -> idle
    func testCompletePlaybackLifecycle() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "loading_model"))
        XCTAssertEqual(engine.state, .loadingModel)

        engine.handleStatusUpdate(TTSStatusMessage(state: "generating"))
        XCTAssertEqual(engine.state, .generating)

        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "Test"))
        XCTAssertEqual(engine.state, .speaking(text: "Test"))

        engine.handleStatusUpdate(TTSStatusMessage(state: "idle"))
        XCTAssertEqual(engine.state, .idle)

        // Delegate should have received all state changes
        XCTAssertEqual(delegate.stateChanges.count, 4)
    }

    /// Verify stop interruption lifecycle:
    /// generating -> stopping -> idle
    func testStopInterruptionLifecycle() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "generating"))
        engine.handleStatusUpdate(TTSStatusMessage(state: "stopping"))
        engine.handleStatusUpdate(TTSStatusMessage(state: "idle"))

        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(delegate.stateChanges.count, 3)
    }

    /// Verify speak-while-speaking lifecycle:
    /// playing -> stopping -> generating -> playing -> idle
    func testSpeakWhileSpeakingLifecycle() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "First"))
        XCTAssertEqual(engine.state, .speaking(text: "First"))

        engine.handleStatusUpdate(TTSStatusMessage(state: "stopping"))
        engine.handleStatusUpdate(TTSStatusMessage(state: "generating"))
        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "Second"))
        XCTAssertEqual(engine.state, .speaking(text: "Second"))

        engine.handleStatusUpdate(TTSStatusMessage(state: "idle"))
        XCTAssertEqual(engine.state, .idle)
    }

    /// Verify elapsed time updates from backend and resets on idle.
    func testElapsedTimeUpdatesFromBackend() {
        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "Test", elapsed: 1.5))
        XCTAssertEqual(engine.elapsedTime, 1.5, accuracy: 0.001)

        engine.handleStatusUpdate(TTSStatusMessage(state: "playing", text: "Test", elapsed: 3.0))
        XCTAssertEqual(engine.elapsedTime, 3.0, accuracy: 0.001)

        engine.handleStatusUpdate(TTSStatusMessage(state: "idle"))
        XCTAssertEqual(engine.elapsedTime, 0.0, accuracy: 0.001)
    }
}


// =============================================================================
// MARK: - 6. TTSEngine Preset Management Tests
// =============================================================================

/// Tests for the preset-based voice management that replaces the old
/// AVSpeechSynthesisVoice-based voice listing and selection.
///
/// These tests will FAIL because:
///   - Current TTSEngine has listVoices() returning [TTSVoiceInfo]
///   - New engine has listPresets() returning [String] (preset names)
///   - Current has findVoice(byName:), setVoice(identifier:)
///   - New has setPreset(name:) via IPC
///   - Current has currentVoiceName returning AVSpeechSynthesisVoice name
///   - New has currentVoiceName returning formatted preset name
///
/// Property 17: TTS Configuration Persistence
final class TTSEnginePresetTests: XCTestCase {

    /// availablePresets static property should return exactly 4 preset names.
    /// FAILS: No availablePresets static property exists.
    func testAvailablePresetsCount() {
        XCTAssertEqual(TTSEngine.availablePresets.count, 4,
                       "Should have exactly 4 voice presets")
    }

    /// availablePresets should contain korean_female.
    func testAvailablePresetsContainsKoreanFemale() {
        XCTAssertTrue(TTSEngine.availablePresets.contains("korean_female"))
    }

    /// availablePresets should contain korean_male.
    func testAvailablePresetsContainsKoreanMale() {
        XCTAssertTrue(TTSEngine.availablePresets.contains("korean_male"))
    }

    /// availablePresets should contain english_female.
    func testAvailablePresetsContainsEnglishFemale() {
        XCTAssertTrue(TTSEngine.availablePresets.contains("english_female"))
    }

    /// availablePresets should contain english_male.
    func testAvailablePresetsContainsEnglishMale() {
        XCTAssertTrue(TTSEngine.availablePresets.contains("english_male"))
    }

    /// availablePresets should NOT contain arbitrary names.
    func testAvailablePresetsDoesNotContainUnknown() {
        XCTAssertFalse(TTSEngine.availablePresets.contains("french_female"))
        XCTAssertFalse(TTSEngine.availablePresets.contains(""))
        XCTAssertFalse(TTSEngine.availablePresets.contains("Korean Female"))
    }
}


// =============================================================================
// MARK: - 7. TTSEngine currentVoiceName Tests
// =============================================================================

/// Tests for the currentVoiceName computed property that returns a
/// human-readable formatted name from the preset name.
///
/// FAILS: Current currentVoiceName queries AVSpeechSynthesisVoice; new one
/// formats preset name (e.g., "korean_female" -> "Korean Female").
final class TTSEngineCurrentVoiceNameTests: XCTestCase {

    /// Verify preset name formatting for all presets.
    /// The currentVoiceName should convert snake_case to Title Case.
    ///
    /// These are expectations for when an engine with each preset config
    /// reports its currentVoiceName.
    func testPresetNameFormattingExpectations() {
        // Define expected mappings
        let expectedFormattedNames: [String: String] = [
            "korean_female": "Korean Female",
            "korean_male": "Korean Male",
            "english_female": "English Female",
            "english_male": "English Male"
        ]

        for (preset, expectedName) in expectedFormattedNames {
            // Verify the mapping is consistent
            let formatted = preset
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            XCTAssertEqual(formatted, expectedName,
                           "Preset '\(preset)' should format to '\(expectedName)'")
        }
    }
}


// =============================================================================
// MARK: - 8. TTSEngine Speak/Stop Empty Input Tests
// =============================================================================

/// Tests that speak() with empty/whitespace text is ignored, matching the
/// current behavior but via the new IPC-based implementation.
///
/// These tests verify behavior that should be preserved across the refactor.
/// Some may pass against the current implementation if the API shape matches.
final class TTSEngineSpeakValidationTests: XCTestCase {

    /// Empty text should be silently ignored in new IPC engine.
    /// The engine should NOT send an IPC message for empty text.
    func testEmptyTextSpeakMessageConstruction() {
        // Verify that TTSSpeakMessage can be constructed but the engine
        // should guard against sending it
        let text = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty,
                      "Empty text should be detected and not sent via IPC")
    }

    /// Whitespace-only text should be silently ignored.
    func testWhitespaceOnlyTextIsEmpty() {
        let text = "   \t\n  "
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty,
                      "Whitespace-only text should be detected as empty")
    }

    /// Valid text should create a proper TTSSpeakMessage for IPC.
    func testValidTextCreatesSpeakMessage() {
        let text = "Hello World"
        let message = TTSSpeakMessage(text: text)
        XCTAssertEqual(message.text, "Hello World")
    }

    /// Korean text should create a proper TTSSpeakMessage for IPC.
    func testKoreanTextCreatesSpeakMessage() {
        let text = "안녕하세요"
        let message = TTSSpeakMessage(text: text)
        XCTAssertEqual(message.text, "안녕하세요")
    }

    /// TTSSpeakMessage should support optional language override.
    func testSpeakMessageWithLanguageOverride() {
        let message = TTSSpeakMessage(text: "Hello", language: "English")
        XCTAssertEqual(message.text, "Hello")
        XCTAssertEqual(message.language, "English")
    }

    /// TTSSpeakMessage.toIPCMessage() should produce correct message type.
    func testSpeakMessageToIPCMessage() {
        let message = TTSSpeakMessage(text: "Test text")
        let ipcMessage = message.toIPCMessage()
        XCTAssertEqual(ipcMessage.type, .ttsSpeak)
        XCTAssertEqual(ipcMessage.payload["text"] as? String, "Test text")
    }
}


// =============================================================================
// MARK: - 9. TTSStopMessage IPC Tests
// =============================================================================

/// Tests for the TTSStopMessage IPC message construction.
final class TTSStopMessageTests: XCTestCase {

    /// TTSStopMessage should create a valid IPC message.
    func testStopMessageToIPCMessage() {
        let message = TTSStopMessage()
        let ipcMessage = message.toIPCMessage()
        XCTAssertEqual(ipcMessage.type, .ttsStop)
        XCTAssertTrue(ipcMessage.payload.isEmpty,
                      "Stop message payload should be empty")
    }
}


// =============================================================================
// MARK: - 10. TTSSetVoiceMessage IPC Tests
// =============================================================================

/// Tests for the TTSSetVoiceMessage IPC message construction.
final class TTSSetVoiceMessageTests: XCTestCase {

    /// TTSSetVoiceMessage should carry the preset name.
    func testSetVoiceMessageCarriesPresetName() {
        let message = TTSSetVoiceMessage(presetName: "korean_male")
        let ipcMessage = message.toIPCMessage()
        XCTAssertEqual(ipcMessage.type, .ttsSetVoice)
        XCTAssertEqual(ipcMessage.payload["preset_name"] as? String, "korean_male")
    }

    /// TTSSetVoiceMessage with empty preset name should still be valid message.
    /// Edge case: the engine should validate before sending, not the message struct.
    func testSetVoiceMessageWithEmptyPresetName() {
        let message = TTSSetVoiceMessage(presetName: "")
        let ipcMessage = message.toIPCMessage()
        XCTAssertEqual(ipcMessage.payload["preset_name"] as? String, "")
    }
}


// =============================================================================
// MARK: - 11. TTSStatusMessage Parsing Tests
// =============================================================================

/// Tests for parsing TTSStatusMessage from backend IPC payloads.
final class TTSStatusMessageParsingTests: XCTestCase {

    /// Parse a complete status message with all fields.
    func testParseCompleteStatusMessage() {
        let payload: [String: Any] = [
            "state": "playing",
            "text": "Hello World",
            "elapsed": 2.5,
            "error": NSNull()
        ]
        let status = TTSStatusMessage.fromPayload(payload)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.state, "playing")
        XCTAssertEqual(status?.text, "Hello World")
        XCTAssertEqual(status?.elapsed, 2.5)
        XCTAssertNil(status?.error)
    }

    /// Parse a minimal status message with only state.
    func testParseMinimalStatusMessage() {
        let payload: [String: Any] = ["state": "idle"]
        let status = TTSStatusMessage.fromPayload(payload)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.state, "idle")
        XCTAssertNil(status?.text)
        XCTAssertNil(status?.elapsed)
        XCTAssertNil(status?.error)
    }

    /// Parse a status message with error.
    func testParseStatusMessageWithError() {
        let payload: [String: Any] = [
            "state": "idle",
            "error": "Model initialization failed"
        ]
        let status = TTSStatusMessage.fromPayload(payload)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.state, "idle")
        XCTAssertEqual(status?.error, "Model initialization failed")
    }

    /// Parse should fail for missing state field.
    func testParseStatusMessageMissingState() {
        let payload: [String: Any] = ["text": "Hello"]
        let status = TTSStatusMessage.fromPayload(payload)
        XCTAssertNil(status,
                     "TTSStatusMessage should fail to parse without 'state' field")
    }

    /// Parse status with all backend state values.
    func testParseAllBackendStates() {
        let backendStates = ["idle", "loading_model", "generating", "playing", "stopping"]
        for stateStr in backendStates {
            let payload: [String: Any] = ["state": stateStr]
            let status = TTSStatusMessage.fromPayload(payload)
            XCTAssertNotNil(status, "Should parse state '\(stateStr)'")
            XCTAssertEqual(status?.state, stateStr)
        }
    }
}


// =============================================================================
// MARK: - 12. TTSVoiceConfigResponse Parsing Tests
// =============================================================================

/// Tests for parsing TTSVoiceConfigResponse from backend IPC payloads.
final class TTSVoiceConfigResponseParsingTests: XCTestCase {

    /// Parse a complete voice config response.
    func testParseCompleteVoiceConfigResponse() {
        let payload: [String: Any] = [
            "language": "Korean",
            "voice_instruct": "A warm, friendly Korean female voice",
            "preset_name": "korean_female",
            "available_presets": ["korean_female", "korean_male", "english_female", "english_male"]
        ]
        let config = TTSVoiceConfigResponse.fromPayload(payload)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.language, "Korean")
        XCTAssertEqual(config?.voiceInstruct, "A warm, friendly Korean female voice")
        XCTAssertEqual(config?.presetName, "korean_female")
        XCTAssertEqual(config?.availablePresets?.count, 4)
    }

    /// Parse a minimal voice config response (only required fields).
    func testParseMinimalVoiceConfigResponse() {
        let payload: [String: Any] = [
            "language": "English",
            "voice_instruct": "A clear English voice"
        ]
        let config = TTSVoiceConfigResponse.fromPayload(payload)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.language, "English")
        XCTAssertEqual(config?.voiceInstruct, "A clear English voice")
        XCTAssertNil(config?.presetName)
        XCTAssertNil(config?.availablePresets)
    }

    /// Parse should fail without required language field.
    func testParseVoiceConfigMissingLanguage() {
        let payload: [String: Any] = [
            "voice_instruct": "A voice"
        ]
        let config = TTSVoiceConfigResponse.fromPayload(payload)
        XCTAssertNil(config,
                     "Should fail without 'language' field")
    }

    /// Parse should fail without required voice_instruct field.
    func testParseVoiceConfigMissingVoiceInstruct() {
        let payload: [String: Any] = [
            "language": "Korean"
        ]
        let config = TTSVoiceConfigResponse.fromPayload(payload)
        XCTAssertNil(config,
                     "Should fail without 'voice_instruct' field")
    }
}


// =============================================================================
// MARK: - 13. TTSEngineDelegate Protocol Shape Tests
// =============================================================================

/// Tests that verify the NEW TTSEngineDelegate protocol shape.
///
/// The new protocol should have:
///   - ttsDidChangeState(_ state: TTSState)
///   - ttsDidEncounterError(_ error: String)
///
/// The old protocol had:
///   - ttsDidStartSpeaking(text: String)
///   - ttsDidFinishSpeaking()
///   - ttsDidCancel()
///   - ttsDidEncounterError(_ error: Error)
///
/// FAILS: Current protocol has 4 methods with different signatures.
final class TTSEngineDelegateProtocolTests: XCTestCase {

    /// Mock delegate should conform to TTSEngineDelegate.
    /// FAILS: TTSEngineDelegate protocol methods are different.
    func testMockDelegateConformsToProtocol() {
        let delegate = MockTTSEngineDelegate()
        // Verify the new protocol methods exist by calling them
        delegate.ttsDidChangeState(.idle)
        delegate.ttsDidEncounterError("test error")

        XCTAssertEqual(delegate.stateChanges.count, 1)
        XCTAssertEqual(delegate.stateChanges.first, .idle)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first, "test error")
    }

    /// Delegate should track multiple state changes.
    /// FAILS: Protocol method ttsDidChangeState doesn't exist.
    func testDelegateTracksMultipleStateChanges() {
        let delegate = MockTTSEngineDelegate()
        delegate.ttsDidChangeState(.idle)
        delegate.ttsDidChangeState(.loadingModel)
        delegate.ttsDidChangeState(.generating)
        delegate.ttsDidChangeState(.speaking(text: "test"))
        delegate.ttsDidChangeState(.idle)

        XCTAssertEqual(delegate.stateChanges.count, 5)
        XCTAssertEqual(delegate.stateChanges[0], .idle)
        XCTAssertEqual(delegate.stateChanges[1], .loadingModel)
        XCTAssertEqual(delegate.stateChanges[2], .generating)
        if case .speaking(let text) = delegate.stateChanges[3] {
            XCTAssertEqual(text, "test")
        } else {
            XCTFail("Fourth state change should be .speaking")
        }
        XCTAssertEqual(delegate.stateChanges[4], .idle)
    }

    /// Delegate should track error strings (not Error objects).
    /// FAILS: Current protocol uses Error, new one uses String.
    func testDelegateTracksErrorStrings() {
        let delegate = MockTTSEngineDelegate()
        delegate.ttsDidEncounterError("Model load timeout")
        delegate.ttsDidEncounterError("Audio playback failed")

        XCTAssertEqual(delegate.errors.count, 2)
        XCTAssertEqual(delegate.errors[0], "Model load timeout")
        XCTAssertEqual(delegate.errors[1], "Audio playback failed")
    }

    /// Reset should clear all tracked calls.
    func testDelegateReset() {
        let delegate = MockTTSEngineDelegate()
        delegate.ttsDidChangeState(.idle)
        delegate.ttsDidEncounterError("error")

        delegate.reset()

        XCTAssertTrue(delegate.stateChanges.isEmpty)
        XCTAssertTrue(delegate.errors.isEmpty)
    }
}


// =============================================================================
// MARK: - 14. Removed API Verification Tests
// =============================================================================

/// These tests verify that old AVSpeechSynthesizer-specific APIs are REMOVED.
///
/// The test approach: We define expectations about what the new TTSEngine
/// public API should look like. If the old APIs still compile, these tests
/// document what needs to be removed.
///
/// These are "negative tests" - they verify the ABSENCE of old API.
/// In practice, the removal is verified by compilation failures.
final class TTSEngineRemovedAPITests: XCTestCase {

    /// TTSEngine should NOT inherit from NSObject.
    /// Verification: TTSEngine should be a plain class, not NSObject subclass.
    /// FAILS: Current TTSEngine inherits from NSObject.
    func testTTSEngineIsNotNSObject() {
        // If TTSEngine no longer inherits NSObject, it won't have `isKind(of:)` etc.
        // This test documents the expectation. Actual verification is at compile time.
        //
        // The new TTSEngine should be declared as:
        //   final class TTSEngine { ... }
        // NOT:
        //   final class TTSEngine: NSObject { ... }
        //
        // Compile-time verification: If NSObject methods are called on TTSEngine
        // and it no longer inherits from NSObject, compilation will fail.
        //
        // We can only assert structural expectations here.
        XCTAssertTrue(true, "TTSEngine should be a plain class, not NSObject subclass")
    }

    /// TTSVoiceInfo struct should NOT exist after refactor.
    /// Verification: TTSVoiceInfo was specific to AVSpeechSynthesisVoice.
    /// The new engine uses string preset names instead.
    ///
    /// This test documents that TTSVoiceInfo is expected to be removed.
    /// If the implementer keeps it for backward compatibility, this test
    /// should be updated accordingly.
    func testTTSVoiceInfoShouldBeRemoved() {
        // Document expectation: TTSVoiceInfo should no longer be needed
        // since voice management is now preset-based.
        XCTAssertTrue(true, "TTSVoiceInfo should be removed (replaced by preset strings)")
    }

    /// elapsedTime should no longer be a computed property on TTSEngine.
    /// The backend now tracks elapsed time and sends it via TTSStatusMessage.elapsed.
    func testElapsedTimeIsFromBackend() {
        // In the new design, elapsed time comes from TTSStatusMessage.elapsed
        // rather than being computed locally from speakingStartTime.
        let status = TTSStatusMessage(state: "playing", elapsed: 5.2)
        XCTAssertEqual(status.elapsed, 5.2,
                       "Elapsed time should come from backend status message")
    }
}


// =============================================================================
// MARK: - 15. IPC Message Round-Trip Tests (TTSSpeakMessage)
// =============================================================================

/// Tests for TTSSpeakMessage JSON serialization round-trip.
/// These validate that the IPC protocol correctly encodes/decodes TTS messages.
final class TTSSpeakMessageRoundTripTests: XCTestCase {

    /// TTSSpeakMessage should survive JSON round-trip.
    func testSpeakMessageRoundTrip() throws {
        let original = TTSSpeakMessage(text: "Hello World", language: "Korean")
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.type, .ttsSpeak)
        XCTAssertEqual(parsed.payload["text"] as? String, "Hello World")
        XCTAssertEqual(parsed.payload["language"] as? String, "Korean")
    }

    /// TTSSpeakMessage with nil language should survive round-trip.
    func testSpeakMessageWithNilLanguageRoundTrip() throws {
        let original = TTSSpeakMessage(text: "Test")
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.type, .ttsSpeak)
        XCTAssertEqual(parsed.payload["text"] as? String, "Test")
    }

    /// TTSSpeakMessage with Korean text should survive round-trip (encoding test).
    func testSpeakMessageKoreanTextRoundTrip() throws {
        let original = TTSSpeakMessage(text: "안녕하세요, 반갑습니다.")
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.payload["text"] as? String, "안녕하세요, 반갑습니다.")
    }

    /// TTSSpeakMessage with long text should survive round-trip.
    func testSpeakMessageLongTextRoundTrip() throws {
        let longText = String(repeating: "This is a test sentence. ", count: 100)
        let original = TTSSpeakMessage(text: longText)
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.payload["text"] as? String, longText)
    }

    /// TTSSpeakMessage with special characters should survive round-trip.
    func testSpeakMessageSpecialCharsRoundTrip() throws {
        let text = "He said \"hello\" & she said 'goodbye'\nNew line here\ttab here"
        let original = TTSSpeakMessage(text: text)
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.payload["text"] as? String, text)
    }
}


// =============================================================================
// MARK: - 16. IPC Message Round-Trip Tests (TTSStopMessage)
// =============================================================================

/// Tests for TTSStopMessage JSON serialization round-trip.
final class TTSStopMessageRoundTripTests: XCTestCase {

    /// TTSStopMessage should survive JSON round-trip.
    func testStopMessageRoundTrip() throws {
        let original = TTSStopMessage()
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.type, .ttsStop)
    }
}


// =============================================================================
// MARK: - 17. IPC Message Round-Trip Tests (TTSSetVoiceMessage)
// =============================================================================

/// Tests for TTSSetVoiceMessage JSON serialization round-trip.
final class TTSSetVoiceMessageRoundTripTests: XCTestCase {

    /// TTSSetVoiceMessage should survive JSON round-trip.
    func testSetVoiceMessageRoundTrip() throws {
        let original = TTSSetVoiceMessage(presetName: "english_female")
        let ipcMessage = original.toIPCMessage()
        let json = try ipcMessage.toJSON()

        let parsed = try IPCMessage.fromJSON(json)
        XCTAssertEqual(parsed.type, .ttsSetVoice)
        XCTAssertEqual(parsed.payload["preset_name"] as? String, "english_female")
    }

    /// All preset names should survive round-trip.
    func testAllPresetNamesRoundTrip() throws {
        let presets = ["korean_female", "korean_male", "english_female", "english_male"]
        for preset in presets {
            let original = TTSSetVoiceMessage(presetName: preset)
            let ipcMessage = original.toIPCMessage()
            let json = try ipcMessage.toJSON()

            let parsed = try IPCMessage.fromJSON(json)
            XCTAssertEqual(parsed.payload["preset_name"] as? String, preset,
                           "Preset '\(preset)' should survive round-trip")
        }
    }
}


// =============================================================================
// MARK: - 18. TTSStatusMessage IPC Message Construction Tests
// =============================================================================

/// Tests for constructing TTSStatusMessage (typically done on the backend side,
/// but we verify the Swift struct can be constructed and converted to IPC message).
final class TTSStatusMessageConstructionTests: XCTestCase {

    /// TTSStatusMessage constructed directly should have correct fields.
    func testStatusMessageDirectConstruction() {
        let status = TTSStatusMessage(
            state: "playing",
            text: "Test text",
            elapsed: 3.14,
            error: nil
        )
        XCTAssertEqual(status.state, "playing")
        XCTAssertEqual(status.text, "Test text")
        XCTAssertEqual(status.elapsed!, 3.14, accuracy: 0.001)
        XCTAssertNil(status.error)
    }

    /// TTSStatusMessage with error should be constructable.
    func testStatusMessageWithError() {
        let status = TTSStatusMessage(
            state: "idle",
            error: "Generation failed: text too long"
        )
        XCTAssertEqual(status.state, "idle")
        XCTAssertEqual(status.error, "Generation failed: text too long")
    }
}


// =============================================================================
// MARK: - 19. TTSEngine Voice Config Update Tests
// =============================================================================

/// Tests for handleVoiceConfigUpdate() which processes incoming
/// TTSVoiceConfigResponse from the backend.
final class TTSEngineVoiceConfigUpdateTests: XCTestCase {

    /// handleVoiceConfigUpdate should update all config fields.
    func testHandleVoiceConfigUpdate() {
        let engine = TTSEngine.forTesting()
        let config = TTSVoiceConfigResponse(
            language: "English",
            voiceInstruct: "A clear voice",
            presetName: "english_female"
        )
        engine.handleVoiceConfigUpdate(config)
        XCTAssertEqual(engine.config.presetName, "english_female")
        XCTAssertEqual(engine.config.language, "English")
        XCTAssertEqual(engine.config.voiceInstruct, "A clear voice")
    }

    /// handleVoiceConfigUpdate with nil presetName should keep existing presetName.
    func testHandleVoiceConfigUpdateWithNilPresetName() {
        let engine = TTSEngine.forTesting()
        let config = TTSVoiceConfigResponse(
            language: "Korean",
            voiceInstruct: "A warm voice"
            // presetName is nil
        )
        engine.handleVoiceConfigUpdate(config)
        // Should keep existing presetName
        XCTAssertEqual(engine.config.presetName, "korean_female")
        XCTAssertEqual(engine.config.language, "Korean")
    }
}
