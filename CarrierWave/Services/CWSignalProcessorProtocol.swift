import Foundation

// MARK: - CWDecoderBackend

/// Available CW signal processing backends
enum CWDecoderBackend: String, CaseIterable, Identifiable {
    /// Bandpass filter with envelope follower (original implementation)
    case bandpass = "Bandpass Filter"

    /// Goertzel algorithm for single-frequency detection
    case goertzel = "Goertzel"

    // MARK: Internal

    var id: String { rawValue }

    var description: String {
        switch self {
        case .bandpass:
            "Uses a digital bandpass filter centered on the tone frequency, " +
                "followed by envelope detection and adaptive thresholding."
        case .goertzel:
            "Uses the Goertzel algorithm for efficient single-frequency detection. " +
                "More computationally efficient for detecting a single tone."
        }
    }

    var shortDescription: String {
        switch self {
        case .bandpass:
            "Filter + Envelope"
        case .goertzel:
            "Goertzel DFT"
        }
    }
}

// MARK: - CWSignalProcessorProtocol

/// Protocol defining the interface for CW signal processors
/// Allows different signal processing backends to be used interchangeably
protocol CWSignalProcessorProtocol: Actor {
    /// Current tone frequency being detected
    var currentToneFrequency: Double { get }

    /// Process an audio buffer and return signal analysis results
    /// - Parameters:
    ///   - samples: Raw audio samples from microphone
    ///   - timestamp: Timestamp of buffer start
    /// - Returns: Signal processing result with key events and visualization data
    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult

    /// Update the tone frequency for detection
    /// - Parameter frequency: New tone frequency in Hz
    func setToneFrequency(_ frequency: Double)

    /// Reset all processor state (call when starting new capture)
    func reset()
}

// MARK: - CWSignalProcessor + CWSignalProcessorProtocol

extension CWSignalProcessor: CWSignalProcessorProtocol {}

// MARK: - GoertzelSignalProcessor + CWSignalProcessorProtocol

extension GoertzelSignalProcessor: CWSignalProcessorProtocol {}
