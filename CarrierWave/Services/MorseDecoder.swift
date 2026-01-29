import Foundation

// MARK: - MorseElement

/// A decoded morse element (dit, dah, or gap)
enum MorseElement: Equatable {
    case dit
    case dah
    case elementGap // Gap within character
    case charGap // Gap between characters
    case wordGap // Gap between words

    var symbol: String {
        switch self {
        case .dit: "."
        case .dah: "-"
        case .elementGap: ""
        case .charGap: " "
        case .wordGap: "  "
        }
    }
}

// MARK: - DecodedOutput

/// Output from the morse decoder
enum DecodedOutput: Equatable {
    /// A character was decoded
    case character(String)

    /// A word gap was detected (space)
    case wordSpace

    /// Raw element for debugging/visualization
    case element(MorseElement)
}

// MARK: - MorseDecoder

/// Decodes morse code from key timing events.
/// Uses adaptive timing to estimate WPM and classify elements.
actor MorseDecoder {
    // MARK: - Configuration

    /// Minimum WPM to consider (prevents unreasonably slow detection)
    private let minWPM: Int = 5

    /// Maximum WPM to consider (prevents unreasonably fast detection)
    private let maxWPM: Int = 60

    /// Initial WPM estimate
    private let initialWPM: Int = 20

    /// Tolerance factor for timing classification (allows for human variation)
    private let timingTolerance: Double = 0.5

    // MARK: - State

    /// Current estimated WPM
    private(set) var estimatedWPM: Int

    /// Estimated unit duration in seconds
    private var unitDuration: TimeInterval

    /// Current morse pattern being assembled
    private var currentPattern: String = ""

    /// Last key state
    private var lastKeyDown: Bool = false

    /// Timestamp of last state change
    private var lastStateChange: TimeInterval = 0

    /// Recent element durations for WPM estimation (key-down only)
    private var recentDurations: [TimeInterval] = []

    /// Maximum durations to keep for averaging
    private let maxDurationSamples: Int = 20

    /// Time since last element (for detecting timeouts)
    private var lastElementTime: TimeInterval = 0

    /// Timeout for completing a character (in unit durations)
    private let charTimeoutUnits: Double = 5.0

    // MARK: - Initialization

    init(initialWPM: Int = 20) {
        self.estimatedWPM = initialWPM
        unitDuration = MorseCode.Timing.unitDuration(forWPM: initialWPM)
    }

    // MARK: - Public API

    /// Process a key state change event
    /// - Parameters:
    ///   - isKeyDown: Whether the key is now down (tone on)
    ///   - timestamp: Time of the event
    /// - Returns: Any decoded output from this event
    func processKeyEvent(isKeyDown: Bool, timestamp: TimeInterval) -> [DecodedOutput] {
        var outputs: [DecodedOutput] = []

        // Initialize on first event
        if lastStateChange == 0 {
            lastStateChange = timestamp
            lastKeyDown = isKeyDown
            lastElementTime = timestamp
            return outputs
        }

        let duration = timestamp - lastStateChange

        if lastKeyDown, !isKeyDown {
            // Key was down, now up: classify the tone duration
            let element = classifyToneDuration(duration)
            outputs.append(.element(element))

            // Add to pattern
            currentPattern += element.symbol

            // Update WPM estimate from this element
            updateWPMEstimate(duration: duration, element: element)

            lastElementTime = timestamp

        } else if !lastKeyDown, isKeyDown {
            // Key was up, now down: classify the gap duration
            let gapOutput = processGap(duration: duration, timestamp: timestamp)
            outputs.append(contentsOf: gapOutput)

            lastElementTime = timestamp
        }

        lastKeyDown = isKeyDown
        lastStateChange = timestamp

        return outputs
    }

    /// Check for timeout and flush any pending character
    /// Call this periodically (e.g., every 100ms) when no key events
    /// - Parameter currentTime: Current timestamp
    /// - Returns: Any decoded output from timeout
    func checkTimeout(currentTime: TimeInterval) -> [DecodedOutput] {
        guard !currentPattern.isEmpty else { return [] }

        let silenceDuration = currentTime - lastElementTime
        let timeoutDuration = unitDuration * charTimeoutUnits

        if silenceDuration > timeoutDuration {
            return flushCurrentCharacter()
        }

        return []
    }

    /// Reset decoder state (call when starting new session)
    func reset() {
        currentPattern = ""
        lastKeyDown = false
        lastStateChange = 0
        lastElementTime = 0
        recentDurations = []
        // Keep current WPM estimate
    }

    /// Reset decoder including WPM estimate
    func fullReset(wpm: Int? = nil) {
        reset()
        estimatedWPM = wpm ?? initialWPM
        unitDuration = MorseCode.Timing.unitDuration(forWPM: estimatedWPM)
    }

    /// Manually set WPM (disables adaptive estimation temporarily)
    func setWPM(_ wpm: Int) {
        estimatedWPM = max(minWPM, min(maxWPM, wpm))
        unitDuration = MorseCode.Timing.unitDuration(forWPM: estimatedWPM)
    }

    // MARK: - Private Methods

    /// Classify a tone (key-down) duration as dit or dah
    private func classifyToneDuration(_ duration: TimeInterval) -> MorseElement {
        // Threshold between dit and dah is 2 units (midpoint of 1 and 3)
        let threshold = unitDuration * 2.0

        // Apply tolerance for edge cases
        let toleranceRange = unitDuration * timingTolerance

        if duration < threshold - toleranceRange {
            return .dit
        } else if duration > threshold + toleranceRange {
            return .dah
        } else {
            // In the fuzzy zone - use ratio to decide
            // Dit = 1 unit, Dah = 3 units
            let ditDistance = abs(duration - unitDuration)
            let dahDistance = abs(duration - unitDuration * 3)
            return ditDistance < dahDistance ? .dit : .dah
        }
    }

    /// Process a gap (key-up) duration
    private func processGap(duration: TimeInterval, timestamp _: TimeInterval) -> [DecodedOutput] {
        var outputs: [DecodedOutput] = []

        // Gap thresholds:
        // Element gap: 1 unit (within character)
        // Character gap: 3 units (between characters)
        // Word gap: 7 units (between words)

        let charGapThreshold = unitDuration * 2.0 // Between 1 and 3 units
        let wordGapThreshold = unitDuration * 5.0 // Between 3 and 7 units

        if duration < charGapThreshold {
            // Element gap - within character, no action needed
            outputs.append(.element(.elementGap))

        } else if duration < wordGapThreshold {
            // Character gap - decode current pattern
            outputs.append(.element(.charGap))
            outputs.append(contentsOf: flushCurrentCharacter())

        } else {
            // Word gap - decode current pattern and add space
            outputs.append(.element(.wordGap))
            outputs.append(contentsOf: flushCurrentCharacter())
            outputs.append(.wordSpace)
        }

        return outputs
    }

    /// Decode and clear the current pattern
    private func flushCurrentCharacter() -> [DecodedOutput] {
        guard !currentPattern.isEmpty else { return [] }

        var outputs: [DecodedOutput] = []

        if let decoded = MorseCode.decode(currentPattern) {
            outputs.append(.character(decoded))
        } else {
            // Unknown pattern - output as-is with marker
            outputs.append(.character("[\(currentPattern)]"))
        }

        currentPattern = ""
        return outputs
    }

    /// Update WPM estimate based on a classified element
    private func updateWPMEstimate(duration: TimeInterval, element: MorseElement) {
        // Only use dits and dahs for estimation
        guard element == .dit || element == .dah else { return }

        // Calculate what the unit duration would be for this element
        let estimatedUnit: TimeInterval
        if element == .dit {
            estimatedUnit = duration / MorseCode.Timing.ditUnits
        } else {
            estimatedUnit = duration / MorseCode.Timing.dahUnits
        }

        // Add to recent samples
        recentDurations.append(estimatedUnit)
        if recentDurations.count > maxDurationSamples {
            recentDurations.removeFirst()
        }

        // Calculate average unit duration
        guard recentDurations.count >= 3 else { return } // Need enough samples

        // Use median for robustness against outliers
        let sorted = recentDurations.sorted()
        let medianUnit = sorted[sorted.count / 2]

        // Update unit duration with smoothing
        let smoothingFactor = 0.3
        unitDuration = unitDuration * (1 - smoothingFactor) + medianUnit * smoothingFactor

        // Clamp to valid range
        let minUnit = MorseCode.Timing.unitDuration(forWPM: maxWPM)
        let maxUnit = MorseCode.Timing.unitDuration(forWPM: minWPM)
        unitDuration = max(minUnit, min(maxUnit, unitDuration))

        // Update WPM
        estimatedWPM = MorseCode.Timing.wpm(fromUnitDuration: unitDuration)
    }
}

// MARK: - MorseDecoderDelegate

/// Protocol for receiving decoded morse output
protocol MorseDecoderDelegate: AnyObject {
    /// Called when a character is decoded
    func morseDecoder(_ decoder: MorseDecoder, didDecode character: String)

    /// Called when a word space is detected
    func morseDecoderDidDetectWordSpace(_ decoder: MorseDecoder)

    /// Called when WPM estimate changes
    func morseDecoder(_ decoder: MorseDecoder, didUpdateWPM wpm: Int)
}
