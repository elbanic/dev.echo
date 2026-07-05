import Foundation
import Accelerate

/// Sample rate converter using vDSP for efficient audio resampling
/// Converts 48kHz audio to 16kHz for MLX-Whisper transcription
struct SampleRateConverter {
    /// Input sample rate (ScreenCaptureKit/AVAudioEngine default)
    let inputSampleRate: Int
    
    /// Output sample rate (MLX-Whisper requirement)
    let outputSampleRate: Int
    
    /// Conversion ratio
    var ratio: Double {
        Double(inputSampleRate) / Double(outputSampleRate)
    }
    
    /// Initialize converter with default rates (48kHz → 16kHz)
    init(from inputRate: Int = 48000, to outputRate: Int = 16000) {
        self.inputSampleRate = inputRate
        self.outputSampleRate = outputRate
    }
    
    /// Convert audio buffer from input sample rate to output sample rate
    /// Uses vDSP for efficient decimation with anti-aliasing
    func convert(buffer: AudioBuffer) -> AudioBuffer {
        let inputSamples = buffer.samples
        
        // If sample rates match, return as-is
        if buffer.sampleRate == outputSampleRate {
            return buffer
        }
        
        // Calculate actual ratio based on buffer's sample rate
        let actualRatio = Double(buffer.sampleRate) / Double(outputSampleRate)
        
        // For 48kHz → 16kHz, ratio is 3
        // Output sample count = input / ratio
        let outputCount = Int(Double(inputSamples.count) / actualRatio)
        
        guard outputCount > 0 else {
            return AudioBuffer(
                samples: [],
                sampleRate: outputSampleRate,
                timestamp: buffer.timestamp,
                source: buffer.source
            )
        }
        
        // Apply low-pass filter before decimation to prevent aliasing
        let filteredSamples = applyLowPassFilter(inputSamples, cutoffRatio: 1.0 / actualRatio)
        
        // Decimate using vDSP
        var outputSamples = [Float](repeating: 0, count: outputCount)
        
        // Use vDSP_desamp for decimation
        // This performs decimation by selecting every Nth sample after filtering
        let decimationFactor = Int(actualRatio)
        
        if decimationFactor == Int(actualRatio) && decimationFactor > 0 {
            // Integer decimation factor - use simple decimation
            for i in 0..<outputCount {
                let sourceIndex = i * decimationFactor
                if sourceIndex < filteredSamples.count {
                    outputSamples[i] = filteredSamples[sourceIndex]
                }
            }
        } else {
            // Non-integer ratio - use linear interpolation
            for i in 0..<outputCount {
                let sourcePosition = Double(i) * actualRatio
                let sourceIndex = Int(sourcePosition)
                let fraction = Float(sourcePosition - Double(sourceIndex))
                
                if sourceIndex + 1 < filteredSamples.count {
                    outputSamples[i] = filteredSamples[sourceIndex] * (1 - fraction) +
                                       filteredSamples[sourceIndex + 1] * fraction
                } else if sourceIndex < filteredSamples.count {
                    outputSamples[i] = filteredSamples[sourceIndex]
                }
            }
        }
        
        return AudioBuffer(
            samples: outputSamples,
            sampleRate: outputSampleRate,
            timestamp: buffer.timestamp,
            source: buffer.source
        )
    }
    
    /// Apply low-pass filter to prevent aliasing during decimation
    /// Uses a simple moving average filter for efficiency
    private func applyLowPassFilter(_ samples: [Float], cutoffRatio: Double) -> [Float] {
        guard samples.count > 0 else { return samples }
        
        // Calculate filter kernel size based on cutoff ratio
        // For 48kHz → 16kHz (ratio 3), we need to filter out frequencies above 8kHz
        let kernelSize = max(3, Int(1.0 / cutoffRatio) * 2 + 1)
        
        // Create normalized filter kernel (simple moving average)
        let kernel = [Float](repeating: 1.0 / Float(kernelSize), count: kernelSize)
        
        // Apply convolution using vDSP
        var output = [Float](repeating: 0, count: samples.count)
        
        vDSP_conv(
            samples, 1,
            kernel, 1,
            &output, 1,
            vDSP_Length(samples.count - kernelSize + 1),
            vDSP_Length(kernelSize)
        )
        
        // Pad the beginning to maintain sample count
        let padSize = kernelSize / 2
        for i in 0..<padSize {
            output[i] = samples[i]
        }
        
        // Copy filtered samples back, accounting for convolution offset
        var result = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            if i < padSize {
                result[i] = samples[i]
            } else if i < samples.count - padSize {
                result[i] = output[i - padSize]
            } else {
                result[i] = samples[i]
            }
        }
        
        return result
    }
    
    /// Calculate expected output sample count for given input count
    func expectedOutputCount(for inputCount: Int, inputRate: Int? = nil) -> Int {
        let rate = inputRate ?? inputSampleRate
        let actualRatio = Double(rate) / Double(outputSampleRate)
        return Int(Double(inputCount) / actualRatio)
    }
}

// MARK: - Convenience Extensions

extension AudioBuffer {
    /// Convert this buffer to a different sample rate
    func converted(to targetSampleRate: Int) -> AudioBuffer {
        let converter = SampleRateConverter(from: sampleRate, to: targetSampleRate)
        return converter.convert(buffer: self)
    }
}
