import MapKit
import SwiftUI

// MARK: - QSOMarkerView

struct QSOMarkerView: View {
    // MARK: Internal

    let annotation: QSOAnnotation
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(markerColor)
                    .frame(width: markerSize, height: markerSize)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                    )

                if annotation.qsoCount > 1 {
                    Text("\(annotation.qsoCount)")
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .shadow(radius: isSelected ? 4 : 2)
            .scaleEffect(isSelected ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }

    // MARK: Private

    private var markerSize: CGFloat {
        switch annotation.qsoCount {
        case 1: 24
        case 2 ... 5: 32
        case 6 ... 20: 40
        default: 48
        }
    }

    private var fontSize: CGFloat {
        switch annotation.qsoCount {
        case 1 ... 5: 10
        case 6 ... 99: 12
        default: 10
        }
    }

    private var markerColor: Color {
        switch annotation.qsoCount {
        case 1: .blue
        case 2 ... 5: .green
        case 6 ... 20: .orange
        default: .red
        }
    }
}

// MARK: - MapFilterSheet

struct MapFilterSheet: View {
    // MARK: Internal

    @Bindable var filterState: MapFilterState

    let availableBands: [String]
    let availableModes: [String]
    let availableParks: [String]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { filterState.startDate ?? Date.distantPast },
                            set: { filterState.startDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { filterState.endDate ?? Date() },
                            set: { filterState.endDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    if filterState.startDate != nil || filterState.endDate != nil {
                        Button("Clear Date Range") {
                            filterState.startDate = nil
                            filterState.endDate = nil
                        }
                    }
                } header: {
                    Text("Date Range")
                }

                Section {
                    Picker("Band", selection: $filterState.selectedBand) {
                        Text("All Bands").tag(String?.none)
                        ForEach(availableBands, id: \.self) { band in
                            Text(band).tag(String?.some(band))
                        }
                    }

                    Picker("Mode", selection: $filterState.selectedMode) {
                        Text("All Modes").tag(String?.none)
                        ForEach(availableModes, id: \.self) { mode in
                            Text(mode).tag(String?.some(mode))
                        }
                    }

                    if !availableParks.isEmpty {
                        Picker("Park", selection: $filterState.selectedPark) {
                            Text("All Parks").tag(String?.none)
                            ForEach(availableParks, id: \.self) { park in
                                Text(park).tag(String?.some(park))
                            }
                        }
                    }
                } header: {
                    Text("Filters")
                }

                Section {
                    Toggle("Confirmed Only", isOn: $filterState.confirmedOnly)
                }

                Section {
                    Toggle("Show Arcs", isOn: $filterState.showArcs)
                } footer: {
                    Text("Draw lines from your grid to contacted stations")
                }

                if filterState.hasActiveFilters {
                    Section {
                        Button("Reset All Filters", role: .destructive) {
                            filterState.resetFilters()
                        }
                    }
                }
            }
            .navigationTitle("Map Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - QSOCalloutView

struct QSOCalloutView: View {
    let annotation: QSOAnnotation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(annotation.gridSquare)
                .font(.headline)

            Text("\(annotation.qsoCount) QSO\(annotation.qsoCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !annotation.callsigns.isEmpty {
                Text(annotation.callsigns.prefix(5).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - MapStatsOverlay

struct MapStatsOverlay: View {
    // MARK: Internal

    let totalQSOs: Int
    let visibleQSOs: Int
    let gridCount: Int

    var body: some View {
        HStack(spacing: 16) {
            statItem(value: visibleQSOs, label: "QSOs")
            statItem(value: gridCount, label: "Grids")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
