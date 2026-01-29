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

    /// Whether still in calibration period
    let isCalibrating: Bool

    /// Current noise floor level (0.0-1.0, normalized)
    let noiseFloor: Float

    /// Current signal-to-noise ratio (higher = cleaner signal)
    let signalToNoiseRatio: Float
}

// MARK: - BiquadFilter

/// Digital biquad bandpass filter using vDSP
/// Isolates CW tone frequency while attenuating noise
struct BiquadFilter {
    // MARK: Lifecycle

    /// Create a bandpass filter centered at the specified frequency
    /// - Parameters:
    ///   - centerFrequency: Center frequency in Hz (typically 500-800 Hz for CW)
    ///   - sampleRate: Audio sample rate
    ///   - q: Q factor (higher = narrower band). Default 5.0 is good for CW
    init(centerFrequency: Double, sampleRate: Double, qFactor: Double = 5.0) {
        // Calculate biquad coefficients for bandpass filter
        // Using Audio EQ Cookbook formulas
        let omega = 2.0 * Double.pi * centerFrequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * qFactor)

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

    // MARK: Internal

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

    // MARK: Private

    // Biquad coefficients: [b0, b1, b2, a1, a2]
    private var coefficients: [Double]
    private var delays: [Double] = [0, 0, 0, 0] // Two delays per section
}

// MARK: - EnvelopeFollower

/// Extracts amplitude envelope from filtered signal
/// Uses fast attack and fast decay for clean CW element detection
struct EnvelopeFollower {
    // MARK: Lifecycle

    /// Create an envelope follower
    /// - Parameters:
    ///   - attackTime: Attack time in seconds (fast, ~3ms for CW)
    ///   - decayTime: Decay time in seconds (fast, ~8ms for CW to catch element gaps)
    ///   - sampleRate: Audio sample rate
    init(attackTime: Double = 0.003, decayTime: Double = 0.008, sampleRate: Double) {
        // Calculate coefficients from time constants
        // coeff = exp(-1 / (time * sampleRate))
        attackCoeff = Float(exp(-1.0 / (attackTime * sampleRate)))
        decayCoeff = Float(exp(-1.0 / (decayTime * sampleRate)))
    }

    // MARK: Internal

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

    // MARK: Private

    private var envelope: Float = 0
    private let attackCoeff: Float
    private let decayCoeff: Float
}

// MARK: - AdaptiveThreshold

/// Adaptive threshold for detecting CW key-down/key-up states
/// Uses both noise floor comparison AND relative drop detection
struct AdaptiveThreshold {
    // MARK: Internal

    /// Current key state
    var currentKeyState: Bool {
        isKeyDown
    }

    /// Whether still in calibration period
    var isCalibrating: Bool {
        sampleCount < minSamplesForDetection
    }

    /// Current noise floor level
    var currentNoiseFloor: Float {
        noiseFloor
    }

    /// Current signal peak level
    var currentSignalPeak: Float {
        signalPeak
    }

    /// Signal-to-noise ratio (signal peak / noise floor)
    var signalToNoiseRatio: Float {
        guard noiseFloor > 0.0001 else {
            return 0
        }
        return signalPeak / noiseFloor
    }

    /// Process envelope samples and detect key state changes
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
            sampleCount += 1

            updateSignalEstimates(sample: sample)

            if sampleCount < minSamplesForDetection {
                logCalibrationProgress()
                continue
            }

            if let event = processSample(sample: sample, timestamp: timestamp) {
                events.append(event)
            }

            logPeriodicStatus(sample: sample)
        }

        return events
    }

    /// Reset threshold state
    mutating func reset() {
        signalPeak = 0
        noiseFloor = 1.0
        isKeyDown = false
        sampleCount = 0
        activeSignalLevel = 0
        lastStateChangeTime = 0
        samplesAboveThreshold = 0
        samplesBelowThreshold = 0
    }

    // MARK: Private

    private var signalPeak: Float = 0
    private var noiseFloor: Float = 1.0 // Start high, will decay to actual noise
    private var isKeyDown = false
    private var sampleCount: Int = 0

    /// Track the active signal level during key-down for relative drop detection
    private var activeSignalLevel: Float = 0

    // Debouncing: track last state change time to avoid rapid toggling
    private var lastStateChangeTime: TimeInterval = 0
    private let minimumStateDuration: TimeInterval = 0.015 // 15ms minimum between state changes

    // Confirmation: require signal to stay above/below threshold for multiple samples
    private var samplesAboveThreshold: Int = 0
    private var samplesBelowThreshold: Int = 0
    private let confirmationSamples: Int = 50 // ~1ms at 44.1kHz, requires sustained signal

    // Adaptation rates
    private let peakDecay: Float = 0.999 // Decay for peak tracking
    private let noiseDecay: Float = 0.995 // Noise floor decays toward quiet level
    private let activeDecay: Float = 0.9995 // Slow decay for active signal tracking
    private let minSamplesForDetection: Int = 100 // Calibration period

    private mutating func updateSignalEstimates(sample: Float) {
        if sample > signalPeak {
            signalPeak = sample
        } else {
            signalPeak *= peakDecay
        }

        if sample < noiseFloor {
            noiseFloor = noiseFloor * 0.9 + sample * 0.1
        } else {
            noiseFloor *= noiseDecay
        }
        noiseFloor = max(noiseFloor, 0.0001)
    }

    private func logCalibrationProgress() {
        guard sampleCount == 1 || sampleCount == 50 || sampleCount == 99 else {
            return
        }
        print("[CW] Cal \(sampleCount)/\(minSamplesForDetection) n:\(String(format: "%.4f", noiseFloor))")
    }

    private mutating func processSample(sample: Float,
                                        timestamp: TimeInterval) -> (isDown: Bool, timestamp: TimeInterval)?
    {
        let ratio = sample / max(noiseFloor, 0.0001)
        let onTh: Float = 8.0, offTh: Float = 5.0, dropTh: Float = 0.35

        // Update confirmation counters
        if ratio > onTh {
            samplesAboveThreshold += 1; samplesBelowThreshold = 0
        } else if ratio < offTh {
            samplesBelowThreshold += 1; samplesAboveThreshold = 0
        } else {
            samplesAboveThreshold = max(0, samplesAboveThreshold - 1); samplesBelowThreshold = max(
                0,
                samplesBelowThreshold - 1
            )
        }

        let timeSince = timestamp - lastStateChangeTime
        let wasKeyDown = isKeyDown
        let relDrop = sample / max(activeSignalLevel, 0.0001)

        // Update key state
        if !isKeyDown {
            if samplesAboveThreshold >= confirmationSamples, timeSince >= minimumStateDuration {
                isKeyDown = true; activeSignalLevel = sample; samplesAboveThreshold = 0
            }
        } else {
            activeSignalLevel = sample > activeSignalLevel ? sample : activeSignalLevel * activeDecay
            if timeSince >= minimumStateDuration, samplesBelowThreshold >= confirmationSamples || relDrop < dropTh {
                isKeyDown = false; samplesBelowThreshold = 0
            }
        }

        if isKeyDown != wasKeyDown {
            let state = isKeyDown ? "DN" : "UP"
            print("[CW] \(state) r:\(String(format: "%.1f", ratio)) d:\(String(format: "%.2f", relDrop))")
            lastStateChangeTime = timestamp
            return (isDown: isKeyDown, timestamp: timestamp)
        }
        return nil
    }

    private func logPeriodicStatus(sample: Float) {
        guard sampleCount.isMultiple(of: 5_000) else {
            return
        }
        let ratio = sample / max(noiseFloor, 0.0001)
        print("[CW] n:\(String(format: "%.4f", noiseFloor)) r:\(String(format: "%.1f", ratio)) k:\(isKeyDown)")
    }
}

// MARK: - CWSignalProcessor

/// Main signal processing pipeline for CW audio
/// Combines bandpass filter, envelope follower, and adaptive threshold
actor CWSignalProcessor {
    // MARK: Lifecycle

    // MARK: - Initialization

    /// Create a signal processor for CW audio
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (typically 44100)
    ///   - toneFrequency: CW sidetone frequency (default 600 Hz)
    ///   - filterQ: Bandpass filter Q factor (default 2.0 for wider passband)
    init(sampleRate: Double, toneFrequency: Double = 600, filterQ: Double = 2.0) {
        self.sampleRate = sampleRate
        self.toneFrequency = toneFrequency

        bandpassFilter = BiquadFilter(
            centerFrequency: toneFrequency,
            sampleRate: sampleRate,
            qFactor: filterQ
        )

        envelopeFollower = EnvelopeFollower(sampleRate: sampleRate)
        threshold = AdaptiveThreshold()
    }

    // MARK: Internal

    /// Get current tone frequency
    var currentToneFrequency: Double {
        toneFrequency
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

        // Update running max for normalization
        if peak > runningMax {
            runningMax = peak
        } else {
            runningMax *= maxDecay
        }

        // Normalize peak to 0-1 range based on running max
        let normalizedPeak = min(1.0, peak / max(runningMax, 0.001))

        // Update visualization buffer (downsample if needed)
        updateVisualizationBuffer(envelope)

        // Calculate noise floor normalized to 0-1 range
        // Use running max for consistent scaling with peak amplitude
        let normalizedNoiseFloor = min(1.0, threshold.currentNoiseFloor / max(runningMax, 0.001))

        return CWSignalResult(
            keyEvents: events,
            peakAmplitude: normalizedPeak,
            isKeyDown: threshold.currentKeyState,
            envelopeSamples: recentEnvelope,
            isCalibrating: threshold.isCalibrating,
            noiseFloor: normalizedNoiseFloor,
            signalToNoiseRatio: threshold.signalToNoiseRatio
        )
    }

    /// Update the tone frequency for the bandpass filter
    /// - Parameter frequency: New tone frequency in Hz
    func setToneFrequency(_ frequency: Double) {
        toneFrequency = frequency
        bandpassFilter = BiquadFilter(
            centerFrequency: frequency,
            sampleRate: sampleRate,
            qFactor: 2.0
        )
        bandpassFilter.reset()
    }

    /// Reset all processor state (call when starting new capture)
    func reset() {
        bandpassFilter.reset()
        envelopeFollower.reset()
        threshold.reset()
        recentEnvelope = []
        runningMax = 0.001
    }

    // MARK: Private

    private var bandpassFilter: BiquadFilter
    private var envelopeFollower: EnvelopeFollower
    private var threshold: AdaptiveThreshold

    private let sampleRate: Double
    private var toneFrequency: Double

    // For visualization - keep last N envelope samples
    private let visualizationSampleCount = 128
    private var recentEnvelope: [Float] = []

    // For level meter normalization - track running max
    private var runningMax: Float = 0.001 // Start with small non-zero value
    private let maxDecay: Float = 0.9999 // Slow decay to track varying levels

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
