import Foundation
import Logging

/// Unified audio capture engine that manages both system audio and microphone capture
/// Handles sample rate conversion and streaming to Python backend via IPC
@available(macOS 13.0, *)
final class AudioCaptureEngine: AudioCaptureDelegate {
    private let systemCapture: SystemAudioCapture
    private let micCapture: MicrophoneCapture
    private let sampleRateConverter: SampleRateConverter
    private let ipcClient: IPCClient
    private var logger: Logger
    
    /// Target sample rate for transcription (MLX-Whisper requirement)
    private let targetSampleRate = 16000
    
    /// Callback for status updates
    var onStatusUpdate: ((AudioSource, CaptureStatus) -> Void)?
    
    /// Callback for permission status updates
    var onPermissionUpdate: ((PermissionStatus) -> Void)?
    
    /// Callback for errors
    var onError: ((AudioCaptureError) -> Void)?
    
    /// Current capture status
    private(set) var systemAudioStatus: CaptureStatus = .inactive
    private(set) var microphoneStatus: CaptureStatus = .inactive
    
    /// Whether microphone capture is enabled (can be toggled by user)
    private(set) var microphoneEnabled: Bool = true
    
    /// Reference to microphone capture for toggle functionality
    private var micCaptureRef: MicrophoneCapture { micCapture }
    
    init(ipcClient: IPCClient, debug: Bool = false) {
        self.systemCapture = SystemAudioCapture(debug: debug)
        self.micCapture = MicrophoneCapture(debug: debug)
        self.sampleRateConverter = SampleRateConverter(from: 48000, to: targetSampleRate)
        self.ipcClient = ipcClient
        self.logger = Logger(label: "dev.echo.audio.engine")
        self.logger.logLevel = debug ? .debug : .warning
        
        // Set delegates
        self.systemCapture.delegate = self
        self.micCapture.delegate = self
    }
    
    /// Update debug mode for all components
    func setDebug(_ debug: Bool) {
        logger.logLevel = debug ? .debug : .warning
        systemCapture.setDebug(debug)
        micCapture.setDebug(debug)
    }
    
    // MARK: - Permission Handling
    
    /// Check all required permissions
    func checkPermissions() async -> PermissionStatus {
        let screenCapture = await systemCapture.checkPermission()
        let microphone = micCapture.checkPermission()
        
        let status = PermissionStatus(
            screenCapture: screenCapture,
            microphone: microphone
        )
        
        onPermissionUpdate?(status)
        return status
    }
    
    /// Request all required permissions
    func requestPermissions() async -> PermissionStatus {
        let screenCapture = await systemCapture.requestPermission()
        let microphone = await micCapture.requestPermission()
        
        let status = PermissionStatus(
            screenCapture: screenCapture,
            microphone: microphone
        )
        
        onPermissionUpdate?(status)
        return status
    }
    
    // MARK: - Capture Control
    
    /// Start capturing both system audio and microphone
    func startCapture() async throws {
        logger.info("Starting audio capture...")
        
        // Connect to IPC server first
        do {
            try await ipcClient.connect()
            logger.info("Connected to IPC server")
        } catch {
            logger.warning("Failed to connect to IPC server: \(error.localizedDescription)")
            logger.warning("Transcription will not be available")
        }
        
        // Check permissions first
        let permissions = await checkPermissions()
        
        if !permissions.screenCapture {
            logger.warning("Screen capture permission not granted")
        }
        
        if !permissions.microphone {
            logger.warning("Microphone permission not granted")
        }
        
        // Start system audio capture
        if permissions.screenCapture {
            do {
                try await systemCapture.startCapture()
                systemAudioStatus = .active
                onStatusUpdate?(.system, .active)
                logger.info("System audio capture started")
            } catch {
                logger.error("Failed to start system audio: \(error.localizedDescription)")
                onError?(error as? AudioCaptureError ?? .captureFailure(underlying: error))
            }
        }
        
        // Start microphone capture
        if permissions.microphone {
            do {
                try micCapture.startCapture()
                microphoneStatus = .active
                onStatusUpdate?(.microphone, .active)
                logger.info("Microphone capture started")
            } catch {
                logger.error("Failed to start microphone: \(error.localizedDescription)")
                onError?(error as? AudioCaptureError ?? .captureFailure(underlying: error))
            }
        }
        
        // Throw if neither could start
        if systemAudioStatus == .inactive && microphoneStatus == .inactive {
            throw AudioCaptureError.permissionDenied
        }
    }
    
    /// Stop all audio capture
    func stopCapture() async {
        logger.info("Stopping audio capture...")
        
        // Stop system audio
        await systemCapture.stopCapture()
        systemAudioStatus = .inactive
        onStatusUpdate?(.system, .inactive)
        
        // Stop microphone
        micCapture.stopCapture()
        microphoneStatus = .inactive
        onStatusUpdate?(.microphone, .inactive)
        
        // Keep IPC connection alive for /chat and /quick commands
        
        logger.info("Audio capture stopped")
    }
    
    /// Check if any capture is active
    var isCapturing: Bool {
        systemAudioStatus == .active || microphoneStatus == .active
    }
    
    /// Toggle microphone capture on/off
    /// Returns the new enabled state
    @discardableResult
    func toggleMicrophone() async -> Bool {
        let shouldEnable = microphoneStatus != .active
        return await setMicrophoneEnabled(shouldEnable)
    }
    
    /// Set microphone capture to specific state
    /// Returns the actual enabled state after the operation
    @discardableResult
    func setMicrophoneEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            // Enable microphone capture
            guard microphoneStatus != .active else {
                // Already active
                microphoneEnabled = true
                return true
            }
            
            let hasPermission = micCapture.checkPermission()
            if hasPermission {
                do {
                    try micCapture.startCapture()
                    microphoneStatus = .active
                    microphoneEnabled = true
                    onStatusUpdate?(.microphone, .active)
                    logger.info("Microphone capture enabled")
                    return true
                } catch {
                    logger.error("Failed to start microphone: \(error.localizedDescription)")
                    microphoneEnabled = false
                    onError?(error as? AudioCaptureError ?? .captureFailure(underlying: error))
                    return false
                }
            } else {
                logger.warning("Microphone permission not granted")
                microphoneEnabled = false
                return false
            }
        } else {
            // Disable microphone capture
            guard microphoneStatus == .active else {
                // Already inactive
                microphoneEnabled = false
                return false
            }
            
            micCapture.stopCapture()
            microphoneStatus = .inactive
            microphoneEnabled = false
            onStatusUpdate?(.microphone, .inactive)
            logger.info("Microphone capture disabled")
            return false
        }
    }
    
    // MARK: - AudioCaptureDelegate
    
    func didCaptureAudio(buffer: AudioBuffer, source: AudioSource) {
        // Convert sample rate for transcription
        let convertedBuffer = sampleRateConverter.convert(buffer: buffer)
        
        // Stream to Python backend via IPC
        Task {
            do {
                try await ipcClient.sendAudioData(convertedBuffer)
            } catch {
                logger.error("Failed to send audio data: \(error.localizedDescription)")
            }
        }
    }
    
    func didEncounterError(error: AudioCaptureError) {
        logger.error("Audio capture error: \(error.localizedDescription)")
        
        // Update status based on error
        switch error {
        case .permissionDenied:
            // Permission was revoked
            Task {
                await stopCapture()
            }
        default:
            break
        }
        
        onError?(error)
    }
}

// MARK: - Fallback for older macOS versions

/// Fallback audio capture engine for macOS versions without ScreenCaptureKit
final class LegacyAudioCaptureEngine: AudioCaptureDelegate {
    private let micCapture: MicrophoneCapture
    private let sampleRateConverter: SampleRateConverter
    private let ipcClient: IPCClient
    private var logger: Logger
    
    private let targetSampleRate = 16000
    
    var onStatusUpdate: ((AudioSource, CaptureStatus) -> Void)?
    var onPermissionUpdate: ((PermissionStatus) -> Void)?
    var onError: ((AudioCaptureError) -> Void)?
    
    private(set) var microphoneStatus: CaptureStatus = .inactive
    
    init(ipcClient: IPCClient, debug: Bool = false) {
        self.micCapture = MicrophoneCapture(debug: debug)
        self.sampleRateConverter = SampleRateConverter(from: 48000, to: targetSampleRate)
        self.ipcClient = ipcClient
        self.logger = Logger(label: "dev.echo.audio.legacy")
        self.logger.logLevel = debug ? .debug : .warning
        self.micCapture.delegate = self
    }
    
    /// Update debug mode
    func setDebug(_ debug: Bool) {
        logger.logLevel = debug ? .debug : .warning
        micCapture.setDebug(debug)
    }
    
    func checkPermissions() async -> PermissionStatus {
        let microphone = micCapture.checkPermission()
        let status = PermissionStatus(screenCapture: false, microphone: microphone)
        onPermissionUpdate?(status)
        return status
    }
    
    func requestPermissions() async -> PermissionStatus {
        let microphone = await micCapture.requestPermission()
        let status = PermissionStatus(screenCapture: false, microphone: microphone)
        onPermissionUpdate?(status)
        return status
    }
    
    func startCapture() async throws {
        logger.warning("ScreenCaptureKit not available - microphone only mode")
        
        let permissions = await checkPermissions()
        
        guard permissions.microphone else {
            throw AudioCaptureError.permissionDenied
        }
        
        try micCapture.startCapture()
        microphoneStatus = .active
        onStatusUpdate?(.microphone, .active)
    }
    
    func stopCapture() async {
        micCapture.stopCapture()
        microphoneStatus = .inactive
        onStatusUpdate?(.microphone, .inactive)
    }
    
    var isCapturing: Bool {
        microphoneStatus == .active
    }
    
    func didCaptureAudio(buffer: AudioBuffer, source: AudioSource) {
        let convertedBuffer = sampleRateConverter.convert(buffer: buffer)
        
        Task {
            do {
                try await ipcClient.sendAudioData(convertedBuffer)
            } catch {
                logger.error("Failed to send audio data: \(error.localizedDescription)")
            }
        }
    }
    
    func didEncounterError(error: AudioCaptureError) {
        logger.error("Audio capture error: \(error.localizedDescription)")
        onError?(error)
    }
}
