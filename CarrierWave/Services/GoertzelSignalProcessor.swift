import Accelerate
import Foundation

// MARK: - GoertzelFilter

/// Goertzel algorithm implementation for efficient single-frequency detection
/// More computationally efficient than FFT when detecting only one frequency
struct GoertzelFilter {
    // MARK: Lifecycle

    /// Create a Goertzel filter for a specific frequency
    /// - Parameters:
    ///   - targetFrequency: The frequency to detect (Hz)
    ///   - sampleRate: Audio sample rate (Hz)
    ///   - blockSize: Number of samples per block (affects frequency resolution)
    init(targetFrequency: Double, sampleRate: Double, blockSize: Int) {
        self.targetFrequency = targetFrequency
        self.sampleRate = sampleRate
        self.blockSize = blockSize

        // Calculate the Goertzel coefficient: 2 * cos(2 * pi * k / N)
        // where k = targetFrequency * N / sampleRate
        let k = targetFrequency * Double(blockSize) / sampleRate
        let omega = 2.0 * Double.pi * k / Double(blockSize)
        coefficient = 2.0 * cos(omega)

        // Pre-calculate for power computation
        cosOmega = cos(omega)
        sinOmega = sin(omega)
    }

    // MARK: Internal

    let targetFrequency: Double
    let sampleRate: Double
    let blockSize: Int
    let coefficient: Double

    /// Process a block of samples and return the magnitude at the target frequency
    /// - Parameter samples: Audio samples (should be exactly blockSize samples)
    /// - Returns: Magnitude at the target frequency (normalized by block size)
    func processSamples(_ samples: [Float]) -> Float {
        var s1: Double = 0.0
        var s2: Double = 0.0

        // Main Goertzel recursion
        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }

        // Compute power: |X[k]|² = s1² + s2² - coeff * s1 * s2
        let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2

        // Return magnitude normalized by block size
        let magnitude = sqrt(max(0, power)) / Double(blockSize)
        return Float(magnitude)
    }

    /// Process samples and return both real and imaginary components
    /// - Parameter samples: Audio samples
    /// - Returns: Tuple of (real, imaginary) components
    func processComplex(_ samples: [Float]) -> (real: Double, imag: Double) {
        var s1: Double = 0.0
        var s2: Double = 0.0

        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }

        // Real = s1 - s2 * cos(omega)
        // Imag = s2 * sin(omega)
        let real = s1 - s2 * cosOmega
        let imag = s2 * sinOmega

        return (real, imag)
    }

    // MARK: Private

    private let cosOmega: Double
    private let sinOmega: Double
}

// MARK: - GoertzelThreshold

/// Adaptive threshold for Goertzel magnitude-based key detection
struct GoertzelThreshold {
    // MARK: Internal

    /// Current key state
    var currentKeyState: Bool {
        isKeyDown
    }

    /// Whether still in calibration period
    var isCalibrating: Bool {
        blockCount < calibrationBlocks
    }

    /// Current noise floor level
    var currentNoiseFloor: Float {
        noiseFloor
    }

    /// Current signal peak level
    var currentSignalPeak: Float {
        signalPeak
    }

    /// Signal-to-noise ratio
    var signalToNoiseRatio: Float {
        guard noiseFloor > 0.0001 else { return 0 }
        return signalPeak / noiseFloor
    }

    /// Process a magnitude value and detect key state changes
    /// - Parameters:
    ///   - magnitude: Goertzel magnitude for this block
    ///   - blockDuration: Duration of the block in seconds
    ///   - blockStartTime: Timestamp of block start
    /// - Returns: Key event if state changed, nil otherwise
    mutating func process(
        magnitude: Float,
        blockDuration: Double,
        blockStartTime: TimeInterval
    ) -> (isDown: Bool, timestamp: TimeInterval)? {
        blockCount += 1

        // Update signal estimates
        updateSignalEstimates(magnitude: magnitude)

        // Don't detect during calibration
        guard !isCalibrating else {
            return nil
        }

        // Calculate threshold dynamically
        let ratio = magnitude / max(noiseFloor, 0.0001)

        // Update confirmation counters
        if ratio > onThreshold {
            blocksAboveThreshold += 1
            blocksBelowThreshold = 0
        } else if ratio < offThreshold {
            blocksBelowThreshold += 1
            blocksAboveThreshold = 0
        } else {
            // In hysteresis zone - gradual decay
            blocksAboveThreshold = max(0, blocksAboveThreshold - 1)
            blocksBelowThreshold = max(0, blocksBelowThreshold - 1)
        }

        let wasKeyDown = isKeyDown
        let timeSinceChange = blockStartTime - lastStateChangeTime

        // State transitions with confirmation
        if !isKeyDown {
            if blocksAboveThreshold >= confirmationBlocks, timeSinceChange >= minimumStateDuration {
                isKeyDown = true
                activeSignalLevel = magnitude
                blocksAboveThreshold = 0
            }
        } else {
            // Update active signal level
            if magnitude > activeSignalLevel {
                activeSignalLevel = magnitude
            } else {
                activeSignalLevel *= activeDecay
            }

            // Check for key-up: either relative drop or absolute threshold
            let relativeDrop = magnitude / max(activeSignalLevel, 0.0001)
            if timeSinceChange >= minimumStateDuration {
                if blocksBelowThreshold >= confirmationBlocks || relativeDrop < dropThreshold {
                    isKeyDown = false
                    blocksBelowThreshold = 0
                }
            }
        }

        // Return event if state changed
        if isKeyDown != wasKeyDown {
            lastStateChangeTime = blockStartTime
            let eventTime = blockStartTime + blockDuration / 2 // Mid-block timing
            return (isDown: isKeyDown, timestamp: eventTime)
        }

        return nil
    }

    /// Reset threshold state
    mutating func reset() {
        signalPeak = 0
        noiseFloor = 1.0
        isKeyDown = false
        blockCount = 0
        activeSignalLevel = 0
        lastStateChangeTime = 0
        blocksAboveThreshold = 0
        blocksBelowThreshold = 0
    }

    // MARK: Private

    private var signalPeak: Float = 0
    private var noiseFloor: Float = 1.0
    private var isKeyDown = false
    private var blockCount: Int = 0
    private var activeSignalLevel: Float = 0
    private var lastStateChangeTime: TimeInterval = 0

    // Confirmation counters
    private var blocksAboveThreshold: Int = 0
    private var blocksBelowThreshold: Int = 0

    // Configuration
    private let calibrationBlocks: Int = 10
    private let confirmationBlocks: Int = 2
    private let minimumStateDuration: TimeInterval = 0.015

    // Thresholds (with hysteresis)
    private let onThreshold: Float = 6.0 // Ratio to trigger key-down
    private let offThreshold: Float = 3.0 // Ratio to trigger key-up
    private let dropThreshold: Float = 0.4 // Relative drop to trigger key-up

    // Adaptation rates
    private let peakDecay: Float = 0.995
    private let noiseDecay: Float = 0.99
    private let activeDecay: Float = 0.98

    private mutating func updateSignalEstimates(magnitude: Float) {
        // Update peak (fast attack, slow decay)
        if magnitude > signalPeak {
            signalPeak = magnitude
        } else {
            signalPeak *= peakDecay
        }

        // Update noise floor (only when magnitude is low)
        if magnitude < noiseFloor {
            noiseFloor = noiseFloor * 0.8 + magnitude * 0.2
        } else if magnitude < noiseFloor * 2 {
            // Slow adaptation when slightly above noise
            noiseFloor *= noiseDecay
        }
        noiseFloor = max(noiseFloor, 0.0001)
    }
}

// MARK: - GoertzelSignalProcessor

/// Signal processor using the Goertzel algorithm for CW tone detection
/// Alternative to bandpass filter approach - more computationally efficient
/// for single-frequency detection
actor GoertzelSignalProcessor {
    // MARK: Lifecycle

    /// Create a Goertzel-based signal processor
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (typically 44100)
    ///   - toneFrequency: CW sidetone frequency (default 600 Hz)
    ///   - blockSize: Samples per Goertzel block (default 128, ~3ms at 44.1kHz)
    init(sampleRate: Double, toneFrequency: Double = 600, blockSize: Int = 128) {
        self.sampleRate = sampleRate
        self.toneFrequency = toneFrequency
        self.blockSize = blockSize

        goertzelFilter = GoertzelFilter(
            targetFrequency: toneFrequency,
            sampleRate: sampleRate,
            blockSize: blockSize
        )
        threshold = GoertzelThreshold()

        blockDuration = Double(blockSize) / sampleRate
    }

    // MARK: Internal

    /// Get current tone frequency
    var currentToneFrequency: Double {
        toneFrequency
    }

    /// Process an audio buffer through the Goertzel pipeline
    /// - Parameters:
    ///   - samples: Raw audio samples from microphone
    ///   - timestamp: Timestamp of buffer start
    /// - Returns: Signal processing result with key events and visualization data
    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult {
        var keyEvents: [(isDown: Bool, timestamp: TimeInterval)] = []
        var magnitudes: [Float] = []

        // Process samples in blocks
        var sampleIndex = 0
        var blockStartTime = timestamp

        // Include leftover samples from previous buffer
        var workingSamples = leftoverSamples + samples
        leftoverSamples = []

        while sampleIndex + blockSize <= workingSamples.count {
            let blockStart = sampleIndex
            let blockEnd = sampleIndex + blockSize
            let block = Array(workingSamples[blockStart ..< blockEnd])

            // Apply Hamming window to reduce spectral leakage
            let windowedBlock = applyHammingWindow(block)

            // Compute Goertzel magnitude
            let magnitude = goertzelFilter.processSamples(windowedBlock)
            magnitudes.append(magnitude)

            // Detect key state changes
            if let event = threshold.process(
                magnitude: magnitude,
                blockDuration: blockDuration,
                blockStartTime: blockStartTime
            ) {
                keyEvents.append(event)
                let state = event.isDown ? "DN" : "UP"
                let ratio = magnitude / max(threshold.currentNoiseFloor, 0.0001)
                print("[CW-G] \(state) mag:\(String(format: "%.4f", magnitude)) r:\(String(format: "%.1f", ratio))")
            }

            sampleIndex += blockSize
            blockStartTime += blockDuration
        }

        // Save leftover samples for next buffer
        if sampleIndex < workingSamples.count {
            leftoverSamples = Array(workingSamples[sampleIndex...])
        }

        // Calculate peak magnitude
        let peakMagnitude = magnitudes.max() ?? 0

        // Update running max for normalization
        if peakMagnitude > runningMax {
            runningMax = peakMagnitude
        } else {
            runningMax *= maxDecay
        }

        // Normalize values for UI
        let normalizedPeak = min(1.0, peakMagnitude / max(runningMax, 0.0001))
        let normalizedNoiseFloor = min(1.0, threshold.currentNoiseFloor / max(runningMax, 0.0001))

        // Build visualization envelope from magnitudes
        updateVisualizationBuffer(magnitudes)

        return CWSignalResult(
            keyEvents: keyEvents,
            peakAmplitude: normalizedPeak,
            isKeyDown: threshold.currentKeyState,
            envelopeSamples: recentMagnitudes,
            isCalibrating: threshold.isCalibrating,
            noiseFloor: normalizedNoiseFloor,
            signalToNoiseRatio: threshold.signalToNoiseRatio
        )
    }

    /// Update the tone frequency
    /// - Parameter frequency: New tone frequency in Hz
    func setToneFrequency(_ frequency: Double) {
        toneFrequency = frequency
        goertzelFilter = GoertzelFilter(
            targetFrequency: frequency,
            sampleRate: sampleRate,
            blockSize: blockSize
        )
    }

    /// Reset all processor state
    func reset() {
        threshold.reset()
        leftoverSamples = []
        recentMagnitudes = []
        runningMax = 0.001
    }

    // MARK: Private

    private var goertzelFilter: GoertzelFilter
    private var threshold: GoertzelThreshold

    private let sampleRate: Double
    private var toneFrequency: Double
    private let blockSize: Int
    private let blockDuration: Double

    // Buffer for samples that don't fill a complete block
    private var leftoverSamples: [Float] = []

    // Visualization
    private let visualizationSampleCount = 128
    private var recentMagnitudes: [Float] = []

    // Normalization
    private var runningMax: Float = 0.001
    private let maxDecay: Float = 0.9995

    // Pre-computed Hamming window
    private lazy var hammingWindow: [Float] = {
        var window = [Float](repeating: 0, count: blockSize)
        for i in 0 ..< blockSize {
            window[i] = Float(0.54 - 0.46 * cos(2.0 * Double.pi * Double(i) / Double(blockSize - 1)))
        }
        return window
    }()

    private func applyHammingWindow(_ samples: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        vDSP_vmul(samples, 1, hammingWindow, 1, &result, 1, vDSP_Length(samples.count))
        return result
    }

    private func updateVisualizationBuffer(_ magnitudes: [Float]) {
        recentMagnitudes.append(contentsOf: magnitudes)

        // Keep only recent samples
        if recentMagnitudes.count > visualizationSampleCount {
            recentMagnitudes.removeFirst(recentMagnitudes.count - visualizationSampleCount)
        }
    }
}
