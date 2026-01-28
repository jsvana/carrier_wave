import MapKit
import SwiftData
import SwiftUI

// MARK: - QSOMapView

struct QSOMapView: View {
    // MARK: Internal

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(annotations) { annotation in
                    Annotation(
                        annotation.displayTitle,
                        coordinate: annotation.coordinate,
                        anchor: .bottom
                    ) {
                        QSOMarkerView(annotation: annotation, isSelected: selectedAnnotation?.id == annotation.id)
                            .onTapGesture {
                                withAnimation {
                                    if selectedAnnotation?.id == annotation.id {
                                        selectedAnnotation = nil
                                    } else {
                                        selectedAnnotation = annotation
                                    }
                                }
                            }
                    }
                }

                if filterState.showArcs {
                    ForEach(arcs) { arc in
                        MapPolyline(coordinates: [arc.from, arc.to])
                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))

            VStack {
                HStack {
                    Spacer()
                    MapStatsOverlay(
                        totalQSOs: allQSOs.count,
                        visibleQSOs: filteredQSOs.count,
                        gridCount: annotations.count
                    )
                }
                .padding()

                Spacer()

                if let annotation = selectedAnnotation {
                    QSOCalloutView(annotation: annotation)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: selectedAnnotation?.id)
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Image(systemName: filterState.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            MapFilterSheet(
                filterState: filterState,
                availableBands: availableBands,
                availableModes: availableModes,
                availableParks: availableParks
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Private

    @Query(sort: \QSO.timestamp, order: .reverse) private var allQSOs: [QSO]

    @State private var filterState = MapFilterState()
    @State private var showingFilterSheet = false
    @State private var selectedAnnotation: QSOAnnotation?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var filteredQSOs: [QSO] {
        allQSOs.filter { qso in
            // Must have their grid
            guard qso.theirGrid?.isEmpty == false else {
                return false
            }

            // Date range filter
            if let start = filterState.startDate, qso.timestamp < start {
                return false
            }
            if let end = filterState.endDate, qso.timestamp > end {
                return false
            }

            // Band filter
            if let band = filterState.selectedBand, qso.band != band {
                return false
            }

            // Mode filter
            if let mode = filterState.selectedMode, qso.mode != mode {
                return false
            }

            // Park filter
            if let park = filterState.selectedPark, qso.parkReference != park {
                return false
            }

            // Confirmed filter
            if filterState.confirmedOnly, !qso.lotwConfirmed {
                return false
            }

            return true
        }
    }

    private var annotations: [QSOAnnotation] {
        // Group QSOs by 4-char grid for clustering
        var gridGroups: [String: [QSO]] = [:]

        for qso in filteredQSOs {
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                continue
            }
            let gridKey = String(grid.prefix(4)).uppercased()
            gridGroups[gridKey, default: []].append(qso)
        }

        return gridGroups.compactMap { gridKey, qsos -> QSOAnnotation? in
            guard let coordinate = MaidenheadConverter.coordinate(from: gridKey) else {
                return nil
            }

            let callsigns = qsos.map(\.callsign).sorted()
            let mostRecent = qsos.map(\.timestamp).max() ?? Date()

            return QSOAnnotation(
                id: gridKey,
                coordinate: coordinate,
                gridSquare: gridKey,
                qsoCount: qsos.count,
                callsigns: callsigns,
                mostRecentDate: mostRecent
            )
        }
    }

    private var arcs: [QSOArc] {
        guard filterState.showArcs else {
            return []
        }

        var result: [QSOArc] = []

        for qso in filteredQSOs {
            guard let myGrid = qso.myGrid,
                  let theirGrid = qso.theirGrid,
                  let from = MaidenheadConverter.coordinate(from: myGrid),
                  let to = MaidenheadConverter.coordinate(from: theirGrid)
            else {
                continue
            }

            result.append(QSOArc(
                id: qso.id.uuidString,
                from: from,
                to: to,
                callsign: qso.callsign
            ))
        }

        return result
    }

    private var availableBands: [String] {
        Array(Set(allQSOs.map(\.band))).sorted { band1, band2 in
            bandSortOrder(band1) < bandSortOrder(band2)
        }
    }

    private var availableModes: [String] {
        Array(Set(allQSOs.map(\.mode))).sorted()
    }

    private var availableParks: [String] {
        Array(Set(allQSOs.compactMap(\.parkReference))).sorted()
    }

    private func bandSortOrder(_ band: String) -> Int {
        let order = ["160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M", "70CM"]
        return order.firstIndex(of: band.uppercased()) ?? 999
    }
}
