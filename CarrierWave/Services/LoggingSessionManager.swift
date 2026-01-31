// swiftlint:disable identifier_name
import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - LoggingSessionManager

/// Manages logging session lifecycle and QSO creation
@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class LoggingSessionManager {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadActiveSession()
    }

    // MARK: Internal

    /// Currently active session
    private(set) var activeSession: LoggingSession?

    /// Service for polling POTA spot comments
    let spotCommentsService = SpotCommentsService()

    /// Whether there's an active session
    var hasActiveSession: Bool {
        activeSession != nil
    }

    /// Start a new logging session
    func startSession(
        myCallsign: String,
        mode: String,
        frequency: Double? = nil,
        activationType: ActivationType = .casual,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        myGrid: String? = nil
    ) {
        // End any existing session first
        if let existing = activeSession {
            existing.end()
        }

        let session = LoggingSession(
            myCallsign: myCallsign,
            startedAt: Date(),
            frequency: frequency,
            mode: mode,
            activationType: activationType,
            parkReference: parkReference,
            sotaReference: sotaReference,
            myGrid: myGrid
        )

        modelContext.insert(session)
        activeSession = session
        saveActiveSessionId(session.id)

        // Prevent screen timeout during active session
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Start auto-spot timer for POTA activations
        startAutoSpotTimer()

        // Start spot comments polling for POTA activations
        startSpotCommentsPolling()

        try? modelContext.save()
    }

    /// End the current session
    func endSession() {
        guard let session = activeSession else {
            return
        }

        session.end()
        activeSession = nil
        clearActiveSessionId()

        // Stop auto-spot timer
        stopAutoSpotTimer()

        // Stop spot comments polling
        spotCommentsService.stopPolling()
        spotCommentsService.clear()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        try? modelContext.save()
    }

    /// Pause the current session
    func pauseSession() {
        guard let session = activeSession else {
            return
        }
        session.pause()

        // Stop auto-spot timer while paused
        stopAutoSpotTimer()

        // Pause spot comments polling
        spotCommentsService.stopPolling()

        try? modelContext.save()
    }

    /// Resume a paused session
    func resumeSession() {
        guard let session = activeSession else {
            return
        }
        session.resume()

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        try? modelContext.save()
    }

    /// Resume a specific session by ID
    func resumeSession(_ session: LoggingSession) {
        // End any existing active session
        if let existing = activeSession, existing.id != session.id {
            existing.end()
            stopAutoSpotTimer()
            spotCommentsService.stopPolling()
        }

        session.resume()
        activeSession = session
        saveActiveSessionId(session.id)

        // Prevent screen timeout during active session
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        try? modelContext.save()
    }

    /// Update operating frequency
    /// For POTA sessions, this also posts a QSY spot if the frequency changed
    func updateFrequency(_ frequency: Double) {
        guard let session = activeSession else {
            return
        }

        let oldFrequency = session.frequency
        session.updateFrequency(frequency)
        try? modelContext.save()

        // Post QSY spot for POTA sessions when frequency actually changed
        if session.activationType == .pota,
           oldFrequency != nil,
           oldFrequency != frequency
        {
            Task {
                await postSpot(comment: "QSY", showToast: true)
            }
        }
    }

    /// Update operating mode
    func updateMode(_ mode: String) {
        activeSession?.updateMode(mode)
        try? modelContext.save()
    }

    /// Update session title
    func updateTitle(_ title: String?) {
        activeSession?.customTitle = title
        try? modelContext.save()
    }

    /// Log a new QSO
    func logQSO(
        callsign: String,
        rstSent: String = "599",
        rstReceived: String = "599",
        theirGrid: String? = nil,
        theirParkReference: String? = nil,
        notes: String? = nil,
        name: String? = nil,
        operatorName: String? = nil,
        state: String? = nil,
        country: String? = nil,
        qth: String? = nil
    ) -> QSO? {
        guard let session = activeSession else {
            return nil
        }

        // Derive band from frequency
        let band: String =
            if let freq = session.frequency {
                LoggingSession.bandForFrequency(freq)
            } else {
                "Unknown"
            }

        let qso = QSO(
            callsign: callsign.uppercased(),
            band: band,
            mode: session.mode,
            frequency: session.frequency,
            timestamp: Date(),
            rstSent: rstSent,
            rstReceived: rstReceived,
            myCallsign: session.myCallsign,
            myGrid: session.myGrid,
            theirGrid: theirGrid,
            parkReference: session.parkReference,
            theirParkReference: theirParkReference,
            notes: combineNotes(notes: notes, operatorName: operatorName),
            importSource: .logger,
            name: name,
            qth: qth,
            state: state,
            country: country
        )

        // Set the logging session ID
        qso.loggingSessionId = session.id

        modelContext.insert(qso)
        session.incrementQSOCount()

        // Mark for upload to configured services
        markForUpload(qso)

        try? modelContext.save()

        return qso
    }

    /// Hide a QSO (soft delete)
    func hideQSO(_ qso: QSO) {
        qso.isHidden = true
        try? modelContext.save()
    }

    /// Unhide a previously hidden QSO
    func unhideQSO(_ qso: QSO) {
        qso.isHidden = false
        try? modelContext.save()
    }

    /// Get recent sessions for resuming
    func getRecentSessions(limit: Int = 10) -> [LoggingSession] {
        let descriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        do {
            var fetchDescriptor = descriptor
            fetchDescriptor.fetchLimit = limit
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            return []
        }
    }

    /// Get QSOs for the current session
    func getSessionQSOs() -> [QSO] {
        guard let session = activeSession else {
            return []
        }

        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId && !qso.isHidden
        }

        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: Private

    private let modelContext: ModelContext

    /// Key for storing active session ID in UserDefaults
    private let activeSessionIdKey = "activeLoggingSessionId"

    /// Timer for auto-spotting to POTA
    private var autoSpotTimer: Timer?

    /// Auto-spot interval (10 minutes)
    private let autoSpotInterval: TimeInterval = 10 * 60

    /// Whether to keep screen on during active session (from settings)
    private var keepScreenOn: Bool {
        UserDefaults.standard.bool(forKey: "loggerKeepScreenOn")
    }

    /// Whether auto-spotting is enabled (from settings)
    private var potaAutoSpotEnabled: Bool {
        UserDefaults.standard.bool(forKey: "potaAutoSpotEnabled")
    }

    /// Start the auto-spot timer for POTA activations
    private func startAutoSpotTimer() {
        stopAutoSpotTimer()

        guard potaAutoSpotEnabled,
              let session = activeSession,
              session.activationType == .pota
        else {
            return
        }

        // Post an initial spot immediately
        Task {
            await postSpot()
        }

        // Schedule recurring spots every 10 minutes
        autoSpotTimer = Timer.scheduledTimer(
            withTimeInterval: autoSpotInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.postSpot()
            }
        }
    }

    /// Stop the auto-spot timer
    private func stopAutoSpotTimer() {
        autoSpotTimer?.invalidate()
        autoSpotTimer = nil
    }

    /// Start spot comments polling for POTA activations
    private func startSpotCommentsPolling() {
        guard let session = activeSession,
              session.activationType == .pota,
              let parkRef = session.parkReference
        else {
            return
        }

        let callsign =
            session.myCallsign ?? UserDefaults.standard.string(
                forKey: "loggerDefaultCallsign"
            ) ?? ""
        guard !callsign.isEmpty else {
            return
        }

        spotCommentsService.startPolling(activator: callsign, parkRef: parkRef)
    }

    /// Post a spot to POTA (used for both auto-spots and QSY spots)
    private func postSpot(comment: String? = nil, showToast: Bool = false) async {
        guard let session = activeSession, session.activationType == .pota,
              let parkRef = session.parkReference, let freq = session.frequency,
              !session.myCallsign.isEmpty
        else {
            return
        }

        do {
            let potaClient = POTAClient(authService: POTAAuthService())
            _ = try await potaClient.postSpot(
                callsign: session.myCallsign, reference: parkRef,
                frequency: freq * 1_000, mode: session.mode, comments: comment
            )
            let msg = comment != nil ? "\(comment!) spot posted" : "Auto-spot posted"
            SyncDebugLog.shared.info("\(msg) for \(parkRef)", service: .pota)
            if showToast {
                ToastManager.shared.spotPosted(
                    park: parkRef, comment: "QSY to \(String(format: "%.3f", freq))"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Spot failed: \(error.localizedDescription)", service: .pota)
        }
    }

    /// Load active session from persisted ID
    private func loadActiveSession() {
        guard let idString = UserDefaults.standard.string(forKey: activeSessionIdKey),
              let sessionId = UUID(uuidString: idString)
        else {
            return
        }

        let predicate = #Predicate<LoggingSession> { session in
            session.id == sessionId
        }

        let descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)

        do {
            let sessions = try modelContext.fetch(descriptor)
            if let session = sessions.first, session.isActive {
                activeSession = session
                // Prevent screen timeout for restored active session
                if keepScreenOn {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                // Restart auto-spot timer for restored POTA session
                startAutoSpotTimer()
                // Restart spot comments polling for restored POTA session
                startSpotCommentsPolling()
            } else {
                // Session was ended or not found, clear the stored ID
                clearActiveSessionId()
            }
        } catch {
            clearActiveSessionId()
        }
    }

    /// Save active session ID to UserDefaults
    private func saveActiveSessionId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeSessionIdKey)
    }

    /// Clear active session ID from UserDefaults
    private func clearActiveSessionId() {
        UserDefaults.standard.removeObject(forKey: activeSessionIdKey)
    }

    /// Combine notes and operator name into a single notes field
    private func combineNotes(notes: String?, operatorName: String?) -> String? {
        var parts: [String] = []

        if let op = operatorName, !op.isEmpty {
            parts.append("OP: \(op)")
        }

        if let n = notes, !n.isEmpty {
            parts.append(n)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    /// Mark QSO for upload to configured services
    private func markForUpload(_ qso: QSO) {
        // Check which services are configured and mark accordingly
        // QRZ
        if (try? KeychainHelper.shared.read(for: KeychainHelper.Keys.qrzApiKey)) != nil {
            qso.markNeedsUpload(to: .qrz, context: modelContext)
        }

        // POTA (only if this is a POTA activation)
        if activeSession?.activationType == .pota,
           UserDefaults.standard.bool(forKey: "pota.authenticated")
        {
            qso.markNeedsUpload(to: .pota, context: modelContext)
        }

        // LoFi
        if UserDefaults.standard.bool(forKey: "lofi.deviceLinked") {
            qso.markNeedsUpload(to: .lofi, context: modelContext)
        }
    }
}
