import SwiftData
import SwiftUI

// MARK: - DashboardView Service Cards

extension DashboardView {
    // MARK: - LoFi Card

    var lofiCard: some View {
        let synced = uploadedCount(for: .lofi)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ham2K LoFi")
                    .font(.headline)
                Spacer()
                if lofiIsConfigured, lofiIsLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Connected")
                    if let callsign = lofiCallsign {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if lofiIsConfigured {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pending connection")
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if lofiIsConfigured, lofiIsLinked {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .lofi)
                } else {
                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(synced) QSOs synced")
                            .font(.subheadline)
                    }

                    if let result = lofiSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode, !syncService.isSyncing {
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .lofi,
                            isDisabled: isSyncing
                        ) {
                            Task { await syncFromLoFi() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                Task { await clearLoFiData() }
                            } label: {
                                Label("Clear LoFi Data", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
                    }
                }
            } else {
                NavigationLink {
                    LoFiSettingsView()
                } label: {
                    Label("Configure", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - QRZ Card

    var qrzCard: some View {
        let inQRZ = uploadedCount(for: .qrz)
        let pending = pendingCount(for: .qrz)
        let confirmed = qsos.filter(\.qrzConfirmed).count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QRZ Logbook")
                    .font(.headline)
                Spacer()
                if qrzIsConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Connected")
                    if let callsign = qrzCallsign {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if qrzIsConfigured {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .qrz)
                } else {
                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(inQRZ) QSOs synced")
                            .font(.subheadline)
                    }

                    // QSL confirmations from QRZ
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(.green)
                        Text("\(confirmed) QSLs confirmed")
                            .font(.subheadline)
                    }

                    // Pending upload
                    if pending > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                            Text("\(pending) pending sync")
                                .font(.subheadline)
                        }
                    }

                    if let result = qrzSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode, !syncService.isSyncing {
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .qrz,
                            isDisabled: isSyncing
                        ) {
                            Task { await performQRZSync() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                Task { await clearQRZData() }
                            } label: {
                                Label("Clear QRZ Data", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
                    }
                }
            } else {
                Button {
                    showingQRZSetup = true
                } label: {
                    Label("Configure", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingQRZSetup) {
            QRZApiKeySheet(
                apiKey: $qrzApiKey,
                callsign: $qrzCallsign,
                isAuthenticated: $qrzIsConfigured,
                errorMessage: $qrzErrorMessage,
                showingError: $showingQRZError
            )
        }
        .alert("Error", isPresented: $showingQRZError) {
            Button("OK") {}
        } message: {
            Text(qrzErrorMessage)
        }
        .onChange(of: qrzIsConfigured) { _, isConfigured in
            if isConfigured {
                loadQRZConfig()
            }
        }
    }

    // MARK: - POTA Card

    @ViewBuilder
    var potaCard: some View {
        let inPOTA = uploadedCount(for: .pota)
        let pending = pendingCount(for: .pota)
        // Check maintenance inline - debugMode and bypassPOTAMaintenance are @AppStorage
        let canBypass = debugMode && bypassPOTAMaintenance
        let isInMaintenance = POTAClient.isInMaintenanceWindow() && !canBypass

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("POTA")
                    .font(.headline)
                Spacer()
                if potaAuth.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Logged in")
                    if let callsign = potaAuth.currentToken?.callsign {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not logged in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if potaAuth.isAuthenticated {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .pota)
                } else {
                    // Session expiry warning
                    if let token = potaAuth.currentToken {
                        if token.isExpiringSoon() {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                Text("Session expires \(token.expiresAt, style: .relative)")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Maintenance window indicator
                    if isInMaintenance {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(.orange)
                            if let remaining = POTAClient.formatMaintenanceTimeRemaining() {
                                Text("Maintenance - \(remaining)")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Maintenance until 0400 UTC")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(inPOTA) QSOs synced")
                            .font(.subheadline)
                    }

                    // Pending
                    if pending > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                            Text("\(pending) pending sync")
                                .font(.subheadline)
                        }
                    }

                    if let result = potaSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode, !syncService.isSyncing {
                    AnimatedSyncButton(
                        title: "Sync",
                        isAnimating: syncingService == .pota,
                        isDisabled: isSyncing || isInMaintenance
                    ) {
                        Task { await performPOTASync() }
                    }
                }
            } else {
                // Show stats even when not logged in
                if inPOTA > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(inPOTA) QSOs synced")
                            .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingPOTALogin) {
            POTALoginSheet(authService: potaAuth)
        }
    }
}

// Secondary service cards (HAMRS, LoTW, iCloud) are in DashboardView+ServiceCardsSecondary.swift
