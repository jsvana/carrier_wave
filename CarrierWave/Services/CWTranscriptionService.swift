import Combine
import Foundation
import SwiftUI

// MARK: - CWTranscriptEntry

/// A single entry in the CW transcript
struct CWTranscriptEntry: Identifiable, Equatable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), timestamp: Date = Date(), text: String, isWordSpace: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        elements = CallsignDetector.parseElements(from: text)
        self.isWordSpace = isWordSpace
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let text: String
    let elements: [CWTextElement]
    let isWordSpace: Bool
}

// MARK: - CWTranscriptionState

/// Current state of the transcription service
enum CWTranscriptionState: Equatable {
    case idle
    case listening
    case error(String)
}

// MARK: - NoiseFloorQuality

/// Quality assessment of the noise floor
enum NoiseFloorQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unusable = "Too Noisy"

    // MARK: Internal

    var color: String {
        switch self {
        case .excellent: "green"
        case .good: "green"
        case .fair: "yellow"
        case .poor: "orange"
        case .unusable: "red"
        }
    }
}

// MARK: - CWTranscriptionService

/// Main service coordinating CW audio capture, signal processing, and decoding.
/// Publishes state updates for UI consumption.
@MainActor
final class CWTranscriptionService: ObservableObject {
    // MARK: Internal

    // MARK: - Published State

    /// Current transcription state
    @Published private(set) var state: CWTranscriptionState = .idle

    /// Estimated WPM from decoder
    @Published private(set) var estimatedWPM: Int = 20

    /// Decoded transcript entries
    @Published private(set) var transcript: [CWTranscriptEntry] = []

    /// Current decoded text line being assembled
    @Published private(set) var currentLine: String = ""

    /// Whether key is currently down (for UI indicator)
    @Published private(set) var isKeyDown: Bool = false

    /// Peak amplitude for level meter (0.0-1.0)
    @Published private(set) var peakAmplitude: Float = 0

    /// Whether still in calibration period
    @Published private(set) var isCalibrating: Bool = true

    /// Recent envelope samples for waveform visualization
    @Published private(set) var waveformSamples: [Float] = []

    /// Current noise floor level (0.0-1.0, normalized)
    @Published private(set) var noiseFloor: Float = 0

    /// Current signal-to-noise ratio
    @Published private(set) var signalToNoiseRatio: Float = 0

    /// Most recently detected callsign from transcript
    @Published private(set) var detectedCallsign: DetectedCallsign?

    /// All callsigns detected in current session
    @Published private(set) var detectedCallsigns: [String] = []

    /// Whether currently listening
    var isListening: Bool {
        state == .listening
    }

    /// Whether noise floor is too high for reliable CW detection
    /// Noise is considered too high when it's above 0.3 (30% of dynamic range)
    var isNoiseTooHigh: Bool {
        noiseFloor > 0.3
    }

    /// Noise floor quality description for UI
    var noiseFloorQuality: NoiseFloorQuality {
        switch noiseFloor {
        case 0 ..< 0.1:
            .excellent
        case 0.1 ..< 0.2:
            .good
        case 0.2 ..< 0.3:
            .fair
        case 0.3 ..< 0.5:
            .poor
        default:
            .unusable
        }
    }

    /// Tone frequency for bandpass filter
    @Published var toneFrequency: Double = 600 {
        didSet {
            Task {
                await signalProcessor?.setToneFrequency(toneFrequency)
            }
        }
    }

    // MARK: - Public API

    /// Start listening and transcribing CW
    func startListening() async {
        guard state != .listening else {
            return
        }

        do {
            // Create fresh instances
            audioCapture = CWAudioCapture()
            guard let capture = audioCapture else {
                return
            }

            let sampleRate = 44_100.0 // Standard sample rate
            signalProcessor = CWSignalProcessor(
                sampleRate: sampleRate,
                toneFrequency: toneFrequency
            )
            morseDecoder = MorseDecoder(initialWPM: estimatedWPM)

            // Start capture
            let audioStream = try await capture.startCapture()
            state = .listening

            // Process audio in background
            captureTask = Task {
                await processAudioStream(audioStream)
            }

            // Start timeout checker
            startTimeoutChecker()
        } catch let error as CWError {
            state = .error(error.localizedDescription)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Stop listening
    func stopListening() {
        captureTask?.cancel()
        captureTask = nil

        timeoutTask?.cancel()
        timeoutTask = nil

        Task {
            await audioCapture?.stopCapture()
            await signalProcessor?.reset()
            await morseDecoder?.reset()
        }

        audioCapture = nil
        state = .idle
        isKeyDown = false
        peakAmplitude = 0
        isCalibrating = true
        noiseFloor = 0
        signalToNoiseRatio = 0
    }

    /// Clear the transcript
    func clearTranscript() {
        transcript = []
        currentLine = ""
        detectedCallsign = nil
        detectedCallsigns = []
    }

    /// Copy transcript to clipboard
    func copyTranscript() -> String {
        let fullText = transcript.map { entry in
            entry.isWordSpace ? " " : entry.text
        }.joined()
        return (fullText + currentLine).trimmingCharacters(in: .whitespaces)
    }

    /// Manually set WPM (overrides adaptive)
    func setWPM(_ wpm: Int) {
        estimatedWPM = wpm
        Task {
            await morseDecoder?.setWPM(wpm)
        }
    }

    // MARK: Private

    // MARK: - Private Properties

    private var audioCapture: CWAudioCapture?
    private var signalProcessor: CWSignalProcessor?
    private var morseDecoder: MorseDecoder?

    private var captureTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    /// Maximum entries to keep in transcript
    private let maxTranscriptEntries = 100

    /// Characters per line before wrapping
    private let lineWrapLength = 40

    // MARK: - Private Methods

    private func processAudioStream(_ stream: AsyncStream<CWAudioCapture.AudioBuffer>) async {
        for await buffer in stream {
            guard !Task.isCancelled else {
                break
            }

            // Process through signal processor
            guard let processor = signalProcessor else {
                continue
            }
            let result = await processor.process(samples: buffer.samples, timestamp: buffer.timestamp)

            // Update UI state
            await MainActor.run {
                self.isKeyDown = result.isKeyDown
                self.peakAmplitude = result.peakAmplitude
                self.waveformSamples = result.envelopeSamples
                self.isCalibrating = result.isCalibrating
                self.noiseFloor = result.noiseFloor
                self.signalToNoiseRatio = result.signalToNoiseRatio
            }

            // Process key events through decoder
            guard let decoder = morseDecoder else {
                continue
            }
            for event in result.keyEvents {
                let outputs = await decoder.processKeyEvent(isKeyDown: event.isDown, timestamp: event.timestamp)
                await processDecoderOutputs(outputs)
            }

            // Update WPM
            let wpm = await decoder.estimatedWPM
            await MainActor.run {
                if self.estimatedWPM != wpm {
                    self.estimatedWPM = wpm
                }
            }
        }
    }

    private func processDecoderOutputs(_ outputs: [DecodedOutput]) async {
        for output in outputs {
            switch output {
            case let .character(char):
                print("[CW] Service received character: '\(char)'")
                await MainActor.run {
                    appendCharacter(char)
                }
            case .wordSpace:
                print("[CW] Service received word space")
                await MainActor.run {
                    appendWordSpace()
                }
            case .element:
                // Raw elements are for debugging, skip for now
                break
            }
        }
    }

    private func appendCharacter(_ char: String) {
        currentLine += char

        // Check for line wrap
        if currentLine.count >= lineWrapLength {
            flushCurrentLine()
        }
    }

    private func appendWordSpace() {
        // Only add space if there's content
        if !currentLine.isEmpty {
            currentLine += " "
        }
    }

    private func flushCurrentLine() {
        guard !currentLine.isEmpty else {
            return
        }

        // Find last space for word boundary
        let text: String
        let remainder: String

        if let lastSpace = currentLine.lastIndex(of: " ") {
            text = String(currentLine[..<lastSpace])
            remainder = String(currentLine[currentLine.index(after: lastSpace)...])
        } else {
            text = currentLine
            remainder = ""
        }

        let entry = CWTranscriptEntry(text: text)
        transcript.append(entry)
        currentLine = remainder

        // Trim old entries
        if transcript.count > maxTranscriptEntries {
            transcript.removeFirst(transcript.count - maxTranscriptEntries)
        }

        // Update detected callsigns
        updateDetectedCallsigns()
    }

    private func updateDetectedCallsigns() {
        // Extract all callsigns from current transcript
        let allText = transcript.map(\.text).joined(separator: " ") + " " + currentLine
        let newCallsigns = CallsignDetector.extractCallsigns(from: allText)

        // Update unique callsigns list
        for callsign in newCallsigns where !detectedCallsigns.contains(callsign) {
            detectedCallsigns.append(callsign)
        }

        // Update primary detected callsign
        if let primary = CallsignDetector.detectPrimaryCallsign(from: transcript) {
            detectedCallsign = primary
        }
    }

    private func startTimeoutChecker() {
        timeoutTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                guard let decoder = morseDecoder else {
                    continue
                }
                let outputs = await decoder.checkTimeout(currentTime: Date().timeIntervalSinceReferenceDate)
                await processDecoderOutputs(outputs)
            }
        }
    }
}
