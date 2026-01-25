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
                if lofiClient.isConfigured, lofiClient.isLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let callsign = lofiClient.getCallsign() {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if lofiClient.isConfigured {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if lofiClient.isConfigured, lofiClient.isLinked {
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
                    Label("Configure LoFi", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - QRZ Card

    var qrzCard: some View {
        let inQRZ = uploadedCount(for: .qrz)
        let pending = pendingCount(for: .qrz)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QRZ Logbook")
                    .font(.headline)
                Spacer()
                if qrzIsConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
                    Label("Configure QRZ", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Task { await loadQRZConfig() }
            }
        }
    }

    // MARK: - POTA Card

    var potaCard: some View {
        let inPOTA = uploadedCount(for: .pota)
        let pending = pendingCount(for: .pota)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("POTA")
                    .font(.headline)
                Spacer()
                if potaAuth.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .pota,
                            isDisabled: isSyncing
                        ) {
                            Task { await performPOTASync() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                potaAuth.logout()
                            } label: {
                                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingPOTALogin) {
            POTALoginSheet(authService: potaAuth)
        }
    }
}

// Secondary service cards (HAMRS, LoTW, iCloud) are in DashboardView+ServiceCardsSecondary.swift
