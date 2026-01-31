// RBN Panel View for Logger
//
// Displays combined RBN and POTA spots for a callsign
// with optional mini-map showing spotter locations.

import MapKit
import SwiftUI

// MARK: - RBNPanelView

struct RBNPanelView: View {
    // MARK: Internal

    /// The callsign to show spots for
    let callsign: String

    /// Optional target callsign (if looking up someone else's spots)
    let targetCallsign: String?

    let onDismiss: () -> Void

    /// The effective callsign to display spots for
    var displayCallsign: String {
        targetCallsign ?? callsign
    }

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

    @State private var spots: [UnifiedSpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showMap = false

    /// Created lazily on first use (view is @MainActor so this is safe)
    private var spotsService: SpotsService {
        SpotsService(
            rbnClient: RBNClient(),
            potaClient: POTAClient(authService: POTAAuthService())
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.up.forward")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 0) {
                Text("Spots")
                    .font(.headline)
                if targetCallsign != nil {
                    Text(displayCallsign)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Text("\(spots.count) spots")
                .font(.caption)
                .foregroundStyle(.secondary)

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
            Text("Loading spots...")
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
            Text("No spots for \(displayCallsign)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if targetCallsign == nil {
                Text("Start transmitting to be spotted!")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var spotsList: some View {
        Group {
            if showMap {
                SpotsMiniMapView(spots: spots)
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

    // swiftlint:disable:next function_body_length
    private func spotRow(_ spot: UnifiedSpot) -> some View {
        HStack(spacing: 12) {
            // Source indicator
            sourceIndicator(spot)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if let spotter = spot.spotter {
                        Text(spotter)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }

                    Spacer()

                    Text(spot.formattedFrequency)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    // RBN-specific: SNR and WPM
                    if let snr = spot.snr {
                        Text("\(snr) dB")
                            .font(.caption)
                            .foregroundStyle(snrColor(snr))
                    }

                    if let wpm = spot.wpm {
                        Text("\(wpm) WPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // POTA-specific: park info
                    if let parkRef = spot.parkRef {
                        Text(parkRef)
                            .font(.caption)
                            .foregroundStyle(.green)
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

                // POTA comments
                if let comments = spot.comments, !comments.isEmpty {
                    Text(comments)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // POTA park name
                if let parkName = spot.parkName, !parkName.isEmpty {
                    Text(parkName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func sourceIndicator(_ spot: UnifiedSpot) -> some View {
        ZStack {
            Circle()
                .fill(sourceColor(spot).opacity(0.2))
                .frame(width: 32, height: 32)

            Image(systemName: sourceIcon(spot))
                .font(.system(size: 14))
                .foregroundStyle(sourceColor(spot))
        }
    }

    // MARK: - Helpers

    private func sourceColor(_ spot: UnifiedSpot) -> Color {
        switch spot.source {
        case .rbn:
            if let snr = spot.snr {
                return snrColor(snr)
            }
            return .blue
        case .pota:
            return .green
        }
    }

    private func sourceIcon(_ spot: UnifiedSpot) -> String {
        switch spot.source {
        case .rbn:
            if let snr = spot.snr {
                return signalIcon(snr: snr)
            }
            return "antenna.radiowaves.left.and.right"
        case .pota:
            return "leaf.fill"
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
            spots = try await spotsService.fetchSpots(for: displayCallsign, hours: 6)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - SpotsMiniMapView

struct SpotsMiniMapView: View {
    // MARK: Internal

    let spots: [UnifiedSpot]

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

    private var spotAnnotations: [SpotMapAnnotation] {
        spots.compactMap { spot in
            guard let grid = spot.spotterGrid,
                  let (lat, lon) = gridToCoordinates(grid)
            else {
                return nil
            }

            let color: Color =
                switch spot.source {
                case .rbn:
                    if let snr = spot.snr {
                        snrColor(snr)
                    } else {
                        .blue
                    }
                case .pota:
                    .green
                }

            return SpotMapAnnotation(
                id: spot.id,
                title: spot.spotter ?? spot.callsign,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                color: color
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

// MARK: - SpotMapAnnotation

private struct SpotMapAnnotation: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

#Preview {
    RBNPanelView(callsign: "W1AW", targetCallsign: nil) {}
        .padding()
}
