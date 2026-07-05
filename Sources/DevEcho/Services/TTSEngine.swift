import Foundation

// MARK: - TTSState

/// Represents the current state of the TTS engine.
/// States mirror the Python backend Qwen3-TTS lifecycle.
enum TTSState: Equatable {
    case idle
    case loadingModel
    case generating
    case speaking(text: String)
    case stopping
}

// MARK: - TTSVoiceConfig

/// Configuration for TTS voice settings using Qwen3-TTS preset-based system.
struct TTSVoiceConfig: Equatable {
    var presetName: String
    var language: String
    var voiceInstruct: String

    /// Default configuration: Korean female voice preset
    static let `default` = TTSVoiceConfig(
        presetName: "korean_female",
        language: "Korean",
        voiceInstruct: "A warm, friendly Korean female voice with clear pronunciation"
    )
}

// MARK: - TTSEngineDelegate

/// Delegate protocol for receiving TTS engine state changes and errors.
protocol TTSEngineDelegate: AnyObject {
    func ttsDidChangeState(_ state: TTSState)
    func ttsDidEncounterError(_ error: String)
}

// MARK: - Preset Formatting

/// Converts a snake_case preset name to Title Case display name.
/// Example: "korean_female" -> "Korean Female"
func formatPresetName(_ presetName: String) -> String {
    presetName
        .split(separator: "_")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}

// MARK: - TTSEngine

/// IPC-based text-to-speech engine that delegates TTS to a Python backend (Qwen3-TTS).
/// State is managed locally but driven by backend status updates via handleStatusUpdate().
final class TTSEngine {
    static let availablePresets = ["korean_female", "korean_male", "english_female", "english_male"]

    private(set) var state: TTSState = .idle
    private(set) var config: TTSVoiceConfig
    weak var delegate: TTSEngineDelegate?
    private let ipcClient: IPCClient?

    /// Elapsed time from backend status
    private(set) var elapsedTime: TimeInterval = 0.0

    /// Current text being spoken (for state tracking)
    private var currentText: String?

    init(ipcClient: IPCClient, config: TTSVoiceConfig = .default) {
        self.ipcClient = ipcClient
        self.config = config
    }

    /// Private initializer for testing without an IPCClient.
    private init(ipcClient: IPCClient?, config: TTSVoiceConfig) {
        self.ipcClient = ipcClient
        self.config = config
    }

    #if DEBUG
    /// Test-only factory that does not require an IPCClient.
    /// IPC methods (speak, stop, setPreset) will be no-ops.
    static func forTesting(config: TTSVoiceConfig = .default) -> TTSEngine {
        return TTSEngine(ipcClient: nil, config: config)
    }
    #endif

    // MARK: - IPC Helpers

    /// Send an IPC message to the backend, logging failures for debuggability.
    /// This is a fire-and-forget helper: errors are logged but not propagated,
    /// because TTS state is driven by backend status updates, not send confirmations.
    private func sendToBackend(_ message: IPCMessage, context: String) {
        guard let client = ipcClient else { return }
        Task { [client] in
            do {
                try await client.send(message)
            } catch {
                // Log IPC send failures for debuggability. These are non-fatal because
                // the backend drives state via handleStatusUpdate(). If the backend is
                // unreachable, state simply won't advance.
                #if DEBUG
                print("[TTSEngine] IPC send failed (\(context)): \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Preload

    /// Preload/warm-up the TTS model on the backend without speaking.
    /// This ensures the first speak() call has minimal latency.
    /// State transitions are driven by the backend via handleStatusUpdate().
    func preload() {
        let message = TTSPreloadMessage()
        sendToBackend(message.toIPCMessage(), context: "preload")
    }

    // MARK: - Speak / Stop

    /// Speak the given text. Empty or whitespace-only text is silently ignored.
    /// If already speaking/generating, stops first then starts new text.
    /// State transitions are driven by the backend via handleStatusUpdate().
    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // If already speaking/generating, stop first.
        // Note: The stop and speak messages are sent sequentially over the same socket,
        // so ordering is preserved. The backend's TTS engine also handles this gracefully
        // by stopping current playback before starting new text in its speak() method.
        if state != .idle && state != .loadingModel {
            stop()
        }

        currentText = text
        let message = TTSSpeakMessage(text: text)
        sendToBackend(message.toIPCMessage(), context: "speak")
    }

    /// Stop current speech.
    /// Always sends stop message to backend (backend handles idle state gracefully).
    /// State transitions are driven by the backend via handleStatusUpdate().
    func stop() {
        let message = TTSStopMessage()
        sendToBackend(message.toIPCMessage(), context: "stop")
    }

    // MARK: - Backend Status Handling

    /// Process incoming TTSStatusMessage from the Python backend.
    /// Maps backend state strings to TTSState enum values.
    func handleStatusUpdate(_ status: TTSStatusMessage) {
        let previousState = state

        switch status.state {
        case "idle":
            state = .idle
            elapsedTime = 0.0
            currentText = nil
        case "loading_model":
            state = .loadingModel
        case "generating":
            state = .generating
        case "playing":
            let text = status.text ?? currentText ?? ""
            state = .speaking(text: text)
            if let elapsed = status.elapsed {
                elapsedTime = elapsed
            }
        case "stopping":
            state = .stopping
        default:
            // Unknown state from backend - ignore silently
            return
        }

        if let error = status.error {
            delegate?.ttsDidEncounterError(error)
        }

        if state != previousState {
            delegate?.ttsDidChangeState(state)
        }
    }

    /// Handle voice config response from backend.
    func handleVoiceConfigUpdate(_ configResponse: TTSVoiceConfigResponse) {
        config = TTSVoiceConfig(
            presetName: configResponse.presetName ?? config.presetName,
            language: configResponse.language,
            voiceInstruct: configResponse.voiceInstruct
        )
    }

    // MARK: - Preset Management

    /// List available preset names.
    func listPresets() -> [String] {
        return Self.availablePresets
    }

    /// Set voice preset by name. Returns true if preset is valid.
    /// Sends IPC message to change backend voice configuration.
    ///
    /// Optimistically updates local config.presetName before backend confirms.
    /// This is safe because presets are validated locally against availablePresets,
    /// so the backend will always accept the value. The backend will also send
    /// a full TTSVoiceConfigResponse via handleVoiceConfigUpdate() that updates
    /// language and voiceInstruct fields with the authoritative values.
    @discardableResult
    func setPreset(name: String) -> Bool {
        guard Self.availablePresets.contains(name) else { return false }

        let message = TTSSetVoiceMessage(presetName: name)
        sendToBackend(message.toIPCMessage(), context: "setPreset(\(name))")

        config.presetName = name
        return true
    }

    /// Current voice name formatted from preset name (snake_case -> Title Case).
    var currentVoiceName: String {
        formatPresetName(config.presetName)
    }
}
