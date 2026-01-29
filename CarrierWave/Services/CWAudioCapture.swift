import AVFoundation
import Foundation

// MARK: - CWAudioCapture

/// Captures audio from the microphone using AVAudioEngine.
/// Uses Swift concurrency to stream audio buffers for processing.
actor CWAudioCapture {
    // MARK: Internal

    // MARK: - Types

    /// Audio buffer with samples and timing information
    struct AudioBuffer {
        let samples: [Float]
        let sampleRate: Double
        let timestamp: TimeInterval
    }

    // MARK: - Public API

    /// Check if currently capturing audio
    var capturing: Bool {
        isCapturing
    }

    /// Request microphone permission
    /// Returns true if permission is granted
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Check current microphone permission status
    static func permissionStatus() -> AVAudioSession.RecordPermission {
        AVAudioSession.sharedInstance().recordPermission
    }

    /// Start capturing audio from the microphone.
    /// Returns an AsyncStream of audio buffers for processing.
    func startCapture() async throws -> AsyncStream<AudioBuffer> {
        guard !isCapturing else {
            throw CWError.processingFailed("Already capturing")
        }

        try await ensureMicrophonePermission()
        try setupAudioSession()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw CWError.noInputAvailable
        }

        let stream = AsyncStream<AudioBuffer> { continuation in
            self.bufferContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.stopCaptureInternal() }
            }
        }

        installAudioTap(on: inputNode, format: inputFormat)

        do {
            try audioEngine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw CWError.audioEngineStartFailed(error)
        }

        return stream
    }

    /// Stop capturing audio
    func stopCapture() {
        stopCaptureInternal()
    }

    // MARK: Private

    private let audioEngine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 1_024 // ~23ms at 44.1kHz
    private var isCapturing = false

    /// Continuation for streaming buffers
    private var bufferContinuation: AsyncStream<AudioBuffer>.Continuation?

    // MARK: - Private Methods

    private func ensureMicrophonePermission() async throws {
        let permission = Self.permissionStatus()
        switch permission {
        case .denied:
            throw CWError.microphonePermissionDenied
        case .undetermined:
            let granted = await Self.requestPermission()
            if !granted {
                throw CWError.microphonePermissionDenied
            }
        case .granted:
            break
        @unknown default:
            throw CWError.microphonePermissionRestricted
        }
    }

    private func installAudioTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format
        ) { [weak self] buffer, time in
            guard let self else {
                return
            }
            guard let channelData = buffer.floatChannelData?[0] else {
                return
            }

            let frameCount = Int(buffer.frameLength)
            var samples = [Float](repeating: 0, count: frameCount)
            for idx in 0 ..< frameCount {
                samples[idx] = channelData[idx]
            }

            let audioBuffer = AudioBuffer(
                samples: samples,
                sampleRate: format.sampleRate,
                timestamp: Double(time.sampleTime) / format.sampleRate
            )

            Task { await self.sendBuffer(audioBuffer) }
        }
    }

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw CWError.audioSessionSetupFailed(error)
        }
    }

    private func sendBuffer(_ buffer: AudioBuffer) {
        bufferContinuation?.yield(buffer)
    }

    private func stopCaptureInternal() {
        guard isCapturing else {
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        bufferContinuation?.finish()
        bufferContinuation = nil

        isCapturing = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
