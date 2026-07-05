import Foundation
import ScreenCaptureKit
import AVFoundation
import Logging

/// Protocol for receiving captured audio data
protocol AudioCaptureDelegate: AnyObject {
    func didCaptureAudio(buffer: AudioBuffer, source: AudioSource)
    func didEncounterError(error: AudioCaptureError)
}

/// Errors that can occur during audio capture
enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case deviceNotAvailable
    case captureFailure(underlying: Error)
    case noDisplayFound
    case streamConfigurationFailed
    case notSupported
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen capture permission denied"
        case .deviceNotAvailable:
            return "Audio device not available"
        case .captureFailure(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .noDisplayFound:
            return "No display found for capture"
        case .streamConfigurationFailed:
            return "Failed to configure capture stream"
        case .notSupported:
            return "ScreenCaptureKit not supported on this system"
        }
    }
}

/// ScreenCaptureKit-based system audio capture handler
/// Captures system audio output (what you hear through speakers/headphones)
/// Note: Audio capture requires macOS 13.0+, video-only capture available on 12.3+
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject {
    weak var delegate: AudioCaptureDelegate?
    
    private var stream: SCStream?
    private var isCapturing = false
    private var logger: Logger
    
    /// Sample rate for captured audio (ScreenCaptureKit default)
    let captureSampleRate: Int = 48000
    
    init(debug: Bool = false) {
        self.logger = Logger(label: "dev.echo.audio.system")
        self.logger.logLevel = debug ? .debug : .warning
        super.init()
    }
    
    /// Update debug mode
    func setDebug(_ debug: Bool) {
        logger.logLevel = debug ? .debug : .warning
    }
    
    /// Check if screen capture permission is granted
    func checkPermission() async -> Bool {
        do {
            // Attempting to get shareable content will prompt for permission if needed
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            return !content.displays.isEmpty
        } catch {
            logger.warning("Permission check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Request screen capture permission
    /// Returns true if permission is granted
    func requestPermission() async -> Bool {
        // On macOS, accessing SCShareableContent triggers the permission dialog
        return await checkPermission()
    }
    
    /// Start capturing system audio
    func startCapture() async throws {
        guard !isCapturing else {
            logger.info("Already capturing")
            return
        }
        
        // Check permission first
        guard await checkPermission() else {
            throw AudioCaptureError.permissionDenied
        }
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }
        
        // Create content filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure stream for audio-only capture
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true  // Don't capture our own audio
        configuration.sampleRate = captureSampleRate
        configuration.channelCount = 1  // Mono for transcription
        
        // Minimize video capture overhead since we only need audio
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps minimum
        configuration.showsCursor = false
        
        // Create and start the stream
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        } catch {
            throw AudioCaptureError.streamConfigurationFailed
        }
        
        do {
            try await stream.startCapture()
            self.stream = stream
            isCapturing = true
            logger.info("System audio capture started at \(captureSampleRate)Hz")
        } catch {
            throw AudioCaptureError.captureFailure(underlying: error)
        }
    }
    
    /// Stop capturing system audio
    func stopCapture() async {
        guard isCapturing, let stream = stream else {
            return
        }
        
        do {
            try await stream.stopCapture()
            logger.info("System audio capture stopped")
        } catch {
            logger.error("Error stopping capture: \(error.localizedDescription)")
        }
        
        self.stream = nil
        isCapturing = false
    }
    
    /// Check if currently capturing
    var capturing: Bool {
        isCapturing
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error.localizedDescription)")
        isCapturing = false
        delegate?.didEncounterError(error: .captureFailure(underlying: error))
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        // Extract audio samples from the sample buffer
        guard let samples = extractAudioSamples(from: sampleBuffer) else {
            return
        }
        
        // Create AudioBuffer and notify delegate
        let audioBuffer = AudioBuffer(
            samples: samples,
            sampleRate: captureSampleRate,
            timestamp: Date(),
            source: .system
        )
        
        delegate?.didCaptureAudio(buffer: audioBuffer, source: .system)
    }
    
    /// Extract Float samples from CMSampleBuffer
    private func extractAudioSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return nil
        }
        
        // Get audio format description
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        
        let bytesPerSample = Int(asbd.pointee.mBytesPerFrame)
        let sampleCount = length / bytesPerSample
        
        // Convert to Float array based on format
        var samples = [Float](repeating: 0, count: sampleCount)
        
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Already float format
            data.withMemoryRebound(to: Float.self, capacity: sampleCount) { floatPtr in
                for i in 0..<sampleCount {
                    samples[i] = floatPtr[i]
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 16 {
            // 16-bit integer format
            data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
                for i in 0..<sampleCount {
                    samples[i] = Float(int16Ptr[i]) / Float(Int16.max)
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 32 {
            // 32-bit integer format
            data.withMemoryRebound(to: Int32.self, capacity: sampleCount) { int32Ptr in
                for i in 0..<sampleCount {
                    samples[i] = Float(int32Ptr[i]) / Float(Int32.max)
                }
            }
        }
        
        return samples
    }
}
