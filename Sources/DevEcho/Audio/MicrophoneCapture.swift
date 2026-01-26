import Foundation
import AVFoundation
import Logging

/// Microphone capture handler using AVAudioEngine
/// Captures microphone input (user's voice)
final class MicrophoneCapture {
    weak var delegate: AudioCaptureDelegate?
    
    private let audioEngine = AVAudioEngine()
    private var isCapturing = false
    private var logger: Logger
    
    /// Sample rate for captured audio
    let captureSampleRate: Int = 48000
    
    /// Buffer size for audio capture
    private let bufferSize: AVAudioFrameCount = 4096
    
    init(debug: Bool = false) {
        self.logger = Logger(label: "dev.echo.audio.mic")
        self.logger.logLevel = debug ? .debug : .warning
    }
    
    /// Update debug mode
    func setDebug(_ debug: Bool) {
        logger.logLevel = debug ? .debug : .warning
    }
    
    /// Check if microphone permission is granted
    func checkPermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Request microphone permission
    /// Returns true if permission is granted
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Start capturing microphone audio
    func startCapture() throws {
        guard !isCapturing else {
            logger.info("Already capturing")
            return
        }
        
        // Check permission
        guard checkPermission() else {
            throw AudioCaptureError.permissionDenied
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Verify we have a valid input format
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.deviceNotAvailable
        }
        
        logger.info("Microphone format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        // Install tap on input node to receive audio buffers
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }
        
        // Start the audio engine
        do {
            try audioEngine.start()
            isCapturing = true
            logger.info("Microphone capture started")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureError.captureFailure(underlying: error)
        }
    }
    
    /// Stop capturing microphone audio
    func stopCapture() {
        guard isCapturing else { return }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        logger.info("Microphone capture stopped")
    }
    
    /// Check if currently capturing
    var capturing: Bool {
        isCapturing
    }
    
    /// Process captured audio buffer
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let floatData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Convert to mono if stereo
        var samples = [Float](repeating: 0, count: frameCount)
        
        if channelCount == 1 {
            // Mono - direct copy
            for i in 0..<frameCount {
                samples[i] = floatData[0][i]
            }
        } else {
            // Stereo - average channels
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += floatData[ch][i]
                }
                samples[i] = sum / Float(channelCount)
            }
        }
        
        // Create AudioBuffer and notify delegate
        let audioBuffer = AudioBuffer(
            samples: samples,
            sampleRate: Int(buffer.format.sampleRate),
            timestamp: Date(),
            source: .microphone
        )
        
        delegate?.didCaptureAudio(buffer: audioBuffer, source: .microphone)
    }
}
