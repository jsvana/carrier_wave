// RBN Panel View for Logger
//
// Displays Reverse Beacon Network spots for the user's callsign
// with optional mini-map showing spotter locations.

import MapKit
import SwiftUI

// MARK: - RBNPanelView

struct RBNPanelView: View {
    // MARK: Internal

    let callsign: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if spots.isEmpty {
                emptyView
            } else {
                spotsList
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadData()
        }
    }

    // MARK: Private

    @State private var spots: [RBNSpot] = []
    @State private var stats: RBNStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showMap = false

    private let rbnClient = RBNClient()

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)

            Text("RBN Spots")
                .font(.headline)

            Spacer()

            if let stats {
                Text("\(stats.totalSpots) spots/hr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showMap.toggle()
            } label: {
                Image(systemName: showMap ? "list.bullet" : "map")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading RBN spots...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots for \(callsign)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Start transmitting to be spotted!")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var spotsList: some View {
        Group {
            if showMap {
                RBNMiniMapView(spots: spots)
                    .frame(height: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(spots) { spot in
                            spotRow(spot)
                            if spot.id != spots.last?.id {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadData() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func spotRow(_ spot: RBNSpot) -> some View {
        HStack(spacing: 12) {
            // Signal strength indicator
            signalIndicator(snr: spot.snr)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spot.spotter)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    Spacer()

                    Text(spot.formattedFrequency)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(spot.snr) dB")
                        .font(.caption)
                        .foregroundStyle(snrColor(spot.snr))

                    if let wpm = spot.wpm {
                        Text("\(wpm) WPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(spot.mode)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    Text(spot.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func signalIndicator(snr: Int) -> some View {
        ZStack {
            Circle()
                .fill(snrColor(snr).opacity(0.2))
                .frame(width: 32, height: 32)

            Image(systemName: signalIcon(snr: snr))
                .font(.system(size: 14))
                .foregroundStyle(snrColor(snr))
        }
    }

    // MARK: - Helpers

    private func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }

    private func signalIcon(snr: Int) -> String {
        switch snr {
        case 25...: "wifi"
        case 15...: "wifi"
        case 5...: "wifi.exclamationmark"
        default: "wifi.slash"
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let spotsTask = rbnClient.spots(for: callsign, hours: 6, limit: 50)
            async let statsTask = rbnClient.stats(hours: 1)

            spots = try await spotsTask
            stats = try? await statsTask

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - RBNMiniMapView

struct RBNMiniMapView: View {
    // MARK: Internal

    let spots: [RBNSpot]

    var body: some View {
        Map {
            ForEach(spotAnnotations) { annotation in
                Marker(annotation.title, coordinate: annotation.coordinate)
                    .tint(annotation.color)
            }
        }
        .mapStyle(.standard)
    }

    // MARK: Private

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
    )

    private var spotAnnotations: [SpotAnnotation] {
        spots.compactMap { spot in
            guard let grid = spot.spotterGrid,
                  let (lat, lon) = gridToCoordinates(grid)
            else {
                return nil
            }

            return SpotAnnotation(
                id: spot.id,
                title: spot.spotter,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                color: snrColor(spot.snr)
            )
        }
    }

    private func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }

    /// Convert a Maidenhead grid square to approximate coordinates
    private func gridToCoordinates(_ grid: String) -> (Double, Double)? {
        let upper = grid.uppercased()
        guard upper.count >= 4 else {
            return nil
        }

        let chars = Array(upper)

        guard let lon1 = chars[0].asciiValue, let lat1 = chars[1].asciiValue,
              lon1 >= 65, lon1 <= 82, lat1 >= 65, lat1 <= 82
        else {
            return nil
        }

        guard let lon2 = chars[2].wholeNumberValue, let lat2 = chars[3].wholeNumberValue else {
            return nil
        }

        var longitude = Double(lon1 - 65) * 20 - 180
        longitude += Double(lon2) * 2 + 1

        var latitude = Double(lat1 - 65) * 10 - 90
        latitude += Double(lat2) + 0.5

        if upper.count >= 6 {
            if let lon3 = chars[4].asciiValue, let lat3 = chars[5].asciiValue,
               lon3 >= 65, lon3 <= 88, lat3 >= 65, lat3 <= 88
            {
                longitude += Double(lon3 - 65) * (2.0 / 24.0) + (1.0 / 24.0)
                latitude += Double(lat3 - 65) * (1.0 / 24.0) + (0.5 / 24.0)
            }
        }

        return (latitude, longitude)
    }
}

// MARK: - SpotAnnotation

private struct SpotAnnotation: Identifiable {
    let id: Int
    let title: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

#Preview {
    RBNPanelView(callsign: "W1AW") {}
        .padding()
}
