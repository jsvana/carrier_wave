import Accelerate
import Foundation

// MARK: - CWSignalResult

/// Result of processing an audio buffer through the CW signal pipeline
struct CWSignalResult {
    /// Key state changes detected in this buffer: (isKeyDown, timestamp)
    let keyEvents: [(isDown: Bool, timestamp: TimeInterval)]

    /// Peak amplitude of the filtered signal (0.0-1.0)
    let peakAmplitude: Float

    /// Current key state at end of buffer
    let isKeyDown: Bool

    /// Recent envelope samples for visualization
    let envelopeSamples: [Float]
}

// MARK: - BiquadFilter

/// Digital biquad bandpass filter using vDSP
/// Isolates CW tone frequency while attenuating noise
struct BiquadFilter {
    // Biquad coefficients: [b0, b1, b2, a1, a2]
    private var coefficients: [Double]
    private var delays: [Double] = [0, 0, 0, 0] // Two delays per section

    /// Create a bandpass filter centered at the specified frequency
    /// - Parameters:
    ///   - centerFrequency: Center frequency in Hz (typically 500-800 Hz for CW)
    ///   - sampleRate: Audio sample rate
    ///   - q: Q factor (higher = narrower band). Default 5.0 is good for CW
    init(centerFrequency: Double, sampleRate: Double, q: Double = 5.0) {
        // Calculate biquad coefficients for bandpass filter
        // Using Audio EQ Cookbook formulas
        let omega = 2.0 * Double.pi * centerFrequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)

        let b0 = alpha
        let b1 = 0.0
        let b2 = -alpha
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha

        // Normalize by a0
        coefficients = [
            b0 / a0, // b0
            b1 / a0, // b1
            b2 / a0, // b2
            a1 / a0, // a1
            a2 / a0, // a2
        ]
    }

    /// Process samples through the bandpass filter
    /// - Parameter samples: Input audio samples
    /// - Returns: Filtered samples
    mutating func process(_ samples: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        // Process using direct form II transposed
        let b0 = Float(coefficients[0])
        let b1 = Float(coefficients[1])
        let b2 = Float(coefficients[2])
        let a1 = Float(coefficients[3])
        let a2 = Float(coefficients[4])

        var z1 = Float(delays[0])
        var z2 = Float(delays[1])

        for i in 0 ..< samples.count {
            let input = samples[i]
            let result = b0 * input + z1
            z1 = b1 * input - a1 * result + z2
            z2 = b2 * input - a2 * result
            output[i] = result
        }

        // Save delays for next buffer
        delays[0] = Double(z1)
        delays[1] = Double(z2)

        return output
    }

    /// Reset filter state (call when starting new capture)
    mutating func reset() {
        delays = [0, 0, 0, 0]
    }
}

// MARK: - EnvelopeFollower

/// Extracts amplitude envelope from filtered signal
/// Uses fast attack and slower decay for clean CW detection
struct EnvelopeFollower {
    private var envelope: Float = 0
    private let attackCoeff: Float
    private let decayCoeff: Float

    /// Create an envelope follower
    /// - Parameters:
    ///   - attackTime: Attack time in seconds (fast, ~5ms for CW)
    ///   - decayTime: Decay time in seconds (slower, ~20ms for CW)
    ///   - sampleRate: Audio sample rate
    init(attackTime: Double = 0.005, decayTime: Double = 0.02, sampleRate: Double) {
        // Calculate coefficients from time constants
        // coeff = exp(-1 / (time * sampleRate))
        attackCoeff = Float(exp(-1.0 / (attackTime * sampleRate)))
        decayCoeff = Float(exp(-1.0 / (decayTime * sampleRate)))
    }

    /// Process samples to extract envelope
    /// - Parameter samples: Filtered audio samples
    /// - Returns: Envelope values (0.0-1.0 range, normalized)
    mutating func process(_ samples: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)
        var maxEnv: Float = 0

        for i in 0 ..< samples.count {
            let rectified = abs(samples[i])

            if rectified > envelope {
                // Attack: fast rise
                envelope = attackCoeff * envelope + (1 - attackCoeff) * rectified
            } else {
                // Decay: slower fall
                envelope = decayCoeff * envelope
            }

            output[i] = envelope
            maxEnv = max(maxEnv, envelope)
        }

        return output
    }

    /// Reset envelope state
    mutating func reset() {
        envelope = 0
    }
}

// MARK: - AdaptiveThreshold

/// Adaptive threshold for detecting CW key-down/key-up states
/// Automatically adjusts to varying signal levels
struct AdaptiveThreshold {
    private var signalPeak: Float = 0
    private var noiseFloor: Float = 0
    private var isKeyDown = false

    // Adaptation rates
    private let peakDecay: Float = 0.9995 // Slow decay for peak tracking
    private let noiseRise: Float = 0.9999 // Very slow rise for noise floor
    private let hysteresis: Float = 0.3 // Hysteresis ratio to prevent chatter

    /// Process envelope samples and detect key state changes
    /// - Parameters:
    ///   - envelope: Envelope samples from EnvelopeFollower
    ///   - sampleRate: Audio sample rate
    ///   - bufferStartTime: Timestamp of buffer start
    /// - Returns: Array of (isKeyDown, timestamp) events
    mutating func process(
        envelope: [Float],
        sampleRate: Double,
        bufferStartTime: TimeInterval
    ) -> [(isDown: Bool, timestamp: TimeInterval)] {
        var events: [(isDown: Bool, timestamp: TimeInterval)] = []
        let samplePeriod = 1.0 / sampleRate

        for i in 0 ..< envelope.count {
            let sample = envelope[i]
            let timestamp = bufferStartTime + Double(i) * samplePeriod

            // Update peak and noise floor estimates
            if sample > signalPeak {
                signalPeak = sample
            } else {
                signalPeak *= peakDecay
            }

            if sample < noiseFloor || noiseFloor == 0 {
                noiseFloor = sample
            } else {
                noiseFloor = noiseFloor * noiseRise + sample * (1 - noiseRise)
            }

            // Ensure minimum separation between peak and noise
            let effectivePeak = max(signalPeak, noiseFloor + 0.01)

            // Calculate threshold with hysteresis
            let range = effectivePeak - noiseFloor
            let onThreshold = noiseFloor + range * (0.5 + hysteresis / 2)
            let offThreshold = noiseFloor + range * (0.5 - hysteresis / 2)

            // Detect state changes
            let wasKeyDown = isKeyDown
            if !isKeyDown, sample > onThreshold {
                isKeyDown = true
            } else if isKeyDown, sample < offThreshold {
                isKeyDown = false
            }

            if isKeyDown != wasKeyDown {
                events.append((isDown: isKeyDown, timestamp: timestamp))
            }
        }

        return events
    }

    /// Current key state
    var currentKeyState: Bool {
        isKeyDown
    }

    /// Reset threshold state
    mutating func reset() {
        signalPeak = 0
        noiseFloor = 0
        isKeyDown = false
    }
}

// MARK: - CWSignalProcessor

/// Main signal processing pipeline for CW audio
/// Combines bandpass filter, envelope follower, and adaptive threshold
actor CWSignalProcessor {
    // MARK: - Properties

    private var bandpassFilter: BiquadFilter
    private var envelopeFollower: EnvelopeFollower
    private var threshold: AdaptiveThreshold

    private let sampleRate: Double
    private var toneFrequency: Double

    // For visualization - keep last N envelope samples
    private let visualizationSampleCount = 128
    private var recentEnvelope: [Float] = []

    // MARK: - Initialization

    /// Create a signal processor for CW audio
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (typically 44100)
    ///   - toneFrequency: CW sidetone frequency (default 600 Hz)
    ///   - filterQ: Bandpass filter Q factor (default 5.0)
    init(sampleRate: Double, toneFrequency: Double = 600, filterQ: Double = 5.0) {
        self.sampleRate = sampleRate
        self.toneFrequency = toneFrequency

        bandpassFilter = BiquadFilter(
            centerFrequency: toneFrequency,
            sampleRate: sampleRate,
            q: filterQ
        )

        envelopeFollower = EnvelopeFollower(sampleRate: sampleRate)
        threshold = AdaptiveThreshold()
    }

    // MARK: - Public API

    /// Process an audio buffer through the complete pipeline
    /// - Parameters:
    ///   - samples: Raw audio samples from microphone
    ///   - timestamp: Timestamp of buffer start
    /// - Returns: Signal processing result with key events and visualization data
    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult {
        // Stage 1: Bandpass filter to isolate CW tone
        let filtered = bandpassFilter.process(samples)

        // Stage 2: Extract envelope
        let envelope = envelopeFollower.process(filtered)

        // Stage 3: Adaptive threshold to detect key states
        let events = threshold.process(
            envelope: envelope,
            sampleRate: sampleRate,
            bufferStartTime: timestamp
        )

        // Calculate peak amplitude for level meter
        var peak: Float = 0
        vDSP_maxv(envelope, 1, &peak, vDSP_Length(envelope.count))

        // Update visualization buffer (downsample if needed)
        updateVisualizationBuffer(envelope)

        return CWSignalResult(
            keyEvents: events,
            peakAmplitude: peak,
            isKeyDown: threshold.currentKeyState,
            envelopeSamples: recentEnvelope
        )
    }

    /// Update the tone frequency for the bandpass filter
    /// - Parameter frequency: New tone frequency in Hz
    func setToneFrequency(_ frequency: Double) {
        toneFrequency = frequency
        bandpassFilter = BiquadFilter(
            centerFrequency: frequency,
            sampleRate: sampleRate,
            q: 5.0
        )
        bandpassFilter.reset()
    }

    /// Reset all processor state (call when starting new capture)
    func reset() {
        bandpassFilter.reset()
        envelopeFollower.reset()
        threshold.reset()
        recentEnvelope = []
    }

    /// Get current tone frequency
    var currentToneFrequency: Double {
        toneFrequency
    }

    // MARK: - Private Methods

    private func updateVisualizationBuffer(_ envelope: [Float]) {
        // Downsample envelope to visualization buffer
        let step = max(1, envelope.count / 16)
        for i in stride(from: 0, to: envelope.count, by: step) {
            recentEnvelope.append(envelope[i])
        }

        // Keep only recent samples
        if recentEnvelope.count > visualizationSampleCount {
            recentEnvelope.removeFirst(recentEnvelope.count - visualizationSampleCount)
        }
    }
}
