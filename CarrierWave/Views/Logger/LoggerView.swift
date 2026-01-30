// swiftlint:disable file_length type_body_length
import SwiftData
import SwiftUI

// MARK: - LoggerView

/// Main logging view for QSO entry
struct LoggerView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if let session = sessionManager?.activeSession {
                        sessionHeader(session)

                        // License warning banner
                        if let violation = currentViolation {
                            LicenseWarningBanner(violation: violation) {
                                dismissedViolation = violation.message
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    } else {
                        noSessionHeader
                    }

                    ScrollView {
                        VStack(spacing: 12) {
                            UnderConstructionBanner()

                            callsignInputSection

                            if let info = lookupResult {
                                LoggerCallsignCard(info: info)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity
                                        )
                                    )
                            }

                            qsoFormSection

                            if showMoreFields {
                                moreFieldsSection
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity
                                        )
                                    )
                            }

                            logButtonSection

                            qsoListSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Logger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sessionMenuButton
                }
            }
            .sheet(isPresented: $showSessionSheet) {
                SessionStartSheet(
                    sessionManager: sessionManager,
                    onDismiss: { showSessionSheet = false }
                )
            }
            .onAppear {
                if sessionManager == nil {
                    sessionManager = LoggingSessionManager(modelContext: modelContext)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lookupResult != nil)
            .animation(.easeInOut(duration: 0.2), value: showMoreFields)
            .animation(.easeInOut(duration: 0.2), value: currentViolation?.message)
            .onChange(of: sessionManager?.activeSession?.frequency) { _, _ in
                dismissedViolation = nil
            }
            .onChange(of: sessionManager?.activeSession?.mode) { _, _ in
                dismissedViolation = nil
            }
            .overlay(alignment: .bottom) {
                panelOverlays
            }
            .alert("Logger Commands", isPresented: $showHelpAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(LoggerCommand.helpText)
            }
            .toastContainer()
            .safeAreaInset(edge: .bottom) {
                if callsignFieldFocused {
                    numberRowAccessory
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: callsignFieldFocused)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect
                {
                    keyboardHeight = frame.height
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                keyboardHeight = 0
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @AppStorage("userLicenseClass") private var licenseClassRaw: String = LicenseClass.extra
        .rawValue

    @Query(
        filter: #Predicate<QSO> { !$0.isHidden },
        sort: \QSO.timestamp,
        order: .reverse
    )
    private var allQSOs: [QSO]

    @State private var sessionManager: LoggingSessionManager?

    @State private var showSessionSheet = false

    // Input fields
    @State private var callsignInput = ""
    @State private var rstSent = "599"
    @State private var rstReceived = "599"
    @State private var showMoreFields = false
    @FocusState private var callsignFieldFocused: Bool

    // Expanded fields
    @State private var notes = ""
    @State private var theirPark = ""
    @State private var operatorName = ""
    @State private var theirGrid = ""

    // Callsign lookup
    @State private var lookupResult: CallsignInfo?
    @State private var lookupTask: Task<Void, Never>?

    // Command panels
    @State private var showRBNPanel = false
    @State private var showSolarPanel = false
    @State private var showWeatherPanel = false
    @State private var showHelpAlert = false

    /// License warning
    @State private var dismissedViolation: String?

    /// Keyboard tracking
    @State private var keyboardHeight: CGFloat = 0

    private var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    /// QSOs for the current session, or recent QSOs if no session
    private var displayQSOs: [QSO] {
        if let session = sessionManager?.activeSession {
            let sessionId = session.id
            return allQSOs.filter { $0.loggingSessionId == sessionId }
        } else {
            // Show most recent 10 QSOs when no session
            return Array(allQSOs.prefix(10))
        }
    }

    /// Whether the log button should be enabled
    private var canLog: Bool {
        sessionManager?.hasActiveSession == true && !callsignInput.isEmpty
            && callsignInput.count >= 3
    }

    /// Current mode (for RST default)
    private var currentMode: String {
        sessionManager?.activeSession?.mode ?? "CW"
    }

    /// Detected command from input (if any)
    private var detectedCommand: LoggerCommand? {
        LoggerCommand.parse(callsignInput)
    }

    /// Current band plan violation (if any)
    private var currentViolation: BandPlanViolation? {
        guard let session = sessionManager?.activeSession,
              let freq = session.frequency
        else {
            return nil
        }

        let violation = BandPlanService.validate(
            frequencyMHz: freq,
            mode: session.mode,
            license: userLicenseClass
        )

        // Don't show if user dismissed this specific violation
        if let violation, violation.message == dismissedViolation {
            return nil
        }

        return violation
    }

    // MARK: - Number Row Accessory

    private var numberRowAccessory: some View {
        HStack(spacing: 8) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "."], id: \.self) { char in
                Button {
                    callsignInput.append(char)
                } label: {
                    Text(char)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Button {
                callsignFieldFocused = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 40)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    /// Panel overlays for RBN, Solar, Weather
    private var panelOverlays: some View {
        VStack {
            if showRBNPanel {
                SwipeToDismissPanel(isPresented: $showRBNPanel) {
                    RBNPanelView(
                        callsign: sessionManager?.activeSession?.myCallsign
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign")
                            ?? "UNKNOWN"
                    ) {
                        showRBNPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showSolarPanel {
                SwipeToDismissPanel(isPresented: $showSolarPanel) {
                    SolarPanelView {
                        showSolarPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showWeatherPanel {
                SwipeToDismissPanel(isPresented: $showWeatherPanel) {
                    WeatherPanelView(
                        grid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
                    ) {
                        showWeatherPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSolarPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showWeatherPanel)
    }

    private var noSessionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("No Active Session")
                    .font(.headline)
                Text("Start a session to begin logging")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showSessionSheet = true
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Session Menu

    private var sessionMenuButton: some View {
        Menu {
            if sessionManager?.hasActiveSession == true {
                Button {
                    sessionManager?.endSession()
                } label: {
                    Label("End Session", systemImage: "stop.fill")
                }

                Button {
                    showSessionSheet = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
            } else {
                Button {
                    showSessionSheet = true
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
            }

            Divider()

            NavigationLink {
                LoggerSettingsView()
            } label: {
                Label("Logger Settings", systemImage: "gear")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Callsign Input

    private var callsignInputSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon changes based on whether input is a command
                if let command = detectedCommand {
                    Image(systemName: command.icon)
                        .foregroundStyle(.purple)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }

                TextField("Callsign or command...", text: $callsignInput)
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(detectedCommand != nil ? .purple : .primary)
                    .focused($callsignFieldFocused)
                    .onSubmit {
                        handleInputSubmit()
                    }
                    .onChange(of: callsignInput) { _, newValue in
                        onCallsignChanged(newValue)
                    }

                if !callsignInput.isEmpty {
                    Button {
                        callsignInput = ""
                        lookupResult = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(detectedCommand != nil ? Color.purple : Color.clear, lineWidth: 2)
            )

            // Command description badge
            if let command = detectedCommand {
                HStack {
                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(.purple)

                    Spacer()

                    Text("Press Return to execute")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: detectedCommand != nil)
    }

    // MARK: - QSO Form

    private var qsoFormSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RST/S")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("599", text: $rstSent)
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("RST/R")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("599", text: $rstReceived)
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                withAnimation {
                    showMoreFields.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showMoreFields ? "chevron.up" : "chevron.down")
                    Text(showMoreFields ? "Less" : "More")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var moreFieldsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Their Grid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("FN31", text: $theirGrid)
                        .font(.subheadline.monospaced())
                        .textInputAutocapitalization(.characters)
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Their Park")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("K-1234", text: $theirPark)
                        .font(.subheadline.monospaced())
                        .textInputAutocapitalization(.characters)
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Operator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Operator name", text: $operatorName)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Notes...", text: $notes, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(2 ... 4)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Log Button

    @ViewBuilder
    private var logButtonSection: some View {
        if let command = detectedCommand {
            // Show "Run Command" button when a command is detected
            Button {
                executeCommand(command)
                callsignInput = ""
            } label: {
                HStack {
                    Image(systemName: command.icon)
                    Text("Run Command")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        } else {
            // Show "Log QSO" button normally
            Button {
                logQSO()
            } label: {
                Text("Log QSO")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canLog)
        }
    }

    // MARK: - QSO List

    private var qsoListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent QSOs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(displayQSOs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if displayQSOs.isEmpty {
                Text("No QSOs yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayQSOs.prefix(10)) { qso in
                    LoggerQSORow(qso: qso)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Session Header

    private func sessionHeader(_ session: LoggingSession) -> some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.headline.monospaced())

                    if let parkName = lookupParkName(session.parkReference) {
                        Text(parkName)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(session.qsoCount) QSOs")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)

                    Text(session.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if let freq = session.frequency {
                    Text(String(format: "%.3f MHz", freq))
                        .font(.caption.monospaced())
                }
                Text(session.mode)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                if let band = session.band {
                    Text(band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func handleInputSubmit() {
        // Check if it's a command
        if let command = LoggerCommand.parse(callsignInput) {
            executeCommand(command)
            callsignInput = ""
            return
        }

        // Otherwise try to log
        if canLog {
            logQSO()
        }
    }

    private func executeCommand(_ command: LoggerCommand) {
        switch command {
        case let .frequency(freq):
            sessionManager?.updateFrequency(freq)
            ToastManager.shared.commandExecuted("FREQ", result: String(format: "%.3f MHz", freq))

        case let .mode(newMode):
            sessionManager?.updateMode(newMode)
            ToastManager.shared.commandExecuted("MODE", result: newMode)

        case .spot:
            Task {
                await postSpot()
            }

        case .rbn:
            showRBNPanel = true

        case .solar:
            showSolarPanel = true

        case .weather:
            showWeatherPanel = true

        case .help:
            showHelpAlert = true
        }
    }

    private func postSpot() async {
        guard let session = sessionManager?.activeSession,
              session.activationType == .pota,
              let parkRef = session.parkReference,
              let freq = session.frequency
        else {
            ToastManager.shared.error("SPOT requires active POTA session with frequency")
            return
        }

        let callsign =
            session.myCallsign ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign")
                ?? ""
        guard !callsign.isEmpty else {
            ToastManager.shared.error("No callsign configured")
            return
        }

        do {
            let potaClient = POTAClient(authService: POTAAuthService())
            let success = try await potaClient.postSpot(
                callsign: callsign,
                reference: parkRef,
                frequency: freq * 1_000, // Convert MHz to kHz
                mode: session.mode ?? "CW"
            )
            if success {
                ToastManager.shared.spotPosted(park: parkRef)
            }
        } catch {
            ToastManager.shared.error("Spot failed: \(error.localizedDescription)")
        }
    }

    private func onCallsignChanged(_ callsign: String) {
        lookupTask?.cancel()

        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()

        // Don't lookup if too short or looks like a command
        guard trimmed.count >= 3,
              LoggerCommand.parse(trimmed) == nil
        else {
            lookupResult = nil
            return
        }

        lookupTask = Task {
            // Small delay to avoid excessive lookups while typing
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else {
                return
            }

            let service = CallsignLookupService(modelContext: modelContext)
            if let info = await service.lookup(trimmed) {
                await MainActor.run {
                    lookupResult = info
                }
            } else {
                await MainActor.run {
                    lookupResult = nil
                }
            }
        }
    }

    private func logQSO() {
        guard canLog else {
            return
        }

        _ = sessionManager?.logQSO(
            callsign: callsignInput,
            rstSent: rstSent.isEmpty ? "599" : rstSent,
            rstReceived: rstReceived.isEmpty ? "599" : rstReceived,
            theirGrid: theirGrid.isEmpty ? nil : theirGrid,
            theirParkReference: theirPark.isEmpty ? nil : theirPark,
            notes: notes.isEmpty ? nil : notes,
            name: lookupResult?.name,
            operatorName: operatorName.isEmpty ? nil : operatorName
        )

        // Reset form
        callsignInput = ""
        lookupResult = nil
        theirGrid = ""
        theirPark = ""
        notes = ""
        operatorName = ""

        // Reset RST to defaults based on mode
        if currentMode == "CW" {
            rstSent = "599"
            rstReceived = "599"
        } else {
            rstSent = "59"
            rstReceived = "59"
        }
    }

    private func lookupParkName(_ reference: String?) -> String? {
        guard let ref = reference else {
            return nil
        }
        // Use the POTA parks cache if available
        return POTAParksCache.shared.name(for: ref)
    }
}

// MARK: - LoggerQSORow

/// A row displaying a logged QSO
struct LoggerQSORow: View {
    // MARK: Internal

    let qso: QSO

    var body: some View {
        HStack(spacing: 12) {
            Text(timeFormatter.string(from: qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(qso.callsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                if let name = qso.name {
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                }
                if let state = qso.state {
                    Text(state)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Frequency or band
                if let freq = qso.frequency {
                    Text(String(format: "%.3f", freq))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(qso.band)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("\(qso.rstSent ?? "599")/\(qso.rstReceived ?? "599")")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Private

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
}

// MARK: - SwipeToDismissPanel

/// Wrapper that adds swipe-to-dismiss gesture to a panel
struct SwipeToDismissPanel<Content: View>: View {
    // MARK: Internal

    @Binding var isPresented: Bool

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging down
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Dismiss if dragged more than 80 points or with velocity
                        if value.translation.height > 80
                            || value.predictedEndTranslation.height > 150
                        {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }
                        // Reset offset
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
    }

    // MARK: Private

    @State private var dragOffset: CGFloat = 0
}

// MARK: - Preview

#Preview {
    LoggerView()
        .modelContainer(
            for: [QSO.self, LoggingSession.self],
            inMemory: true
        )
}
