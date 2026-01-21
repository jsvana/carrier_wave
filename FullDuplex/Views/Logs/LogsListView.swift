import SwiftUI
import SwiftData

struct LogsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QSO.timestamp, order: .reverse) private var qsos: [QSO]

    @State private var searchText = ""
    @State private var selectedBand: String?
    @State private var selectedMode: String?

    private var filteredQSOs: [QSO] {
        qsos.filter { qso in
            let matchesSearch = searchText.isEmpty ||
                qso.callsign.localizedCaseInsensitiveContains(searchText) ||
                (qso.parkReference?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesBand = selectedBand == nil || qso.band == selectedBand
            let matchesMode = selectedMode == nil || qso.mode == selectedMode

            return matchesSearch && matchesBand && matchesMode
        }
    }

    private var availableBands: [String] {
        Array(Set(qsos.map(\.band))).sorted()
    }

    private var availableModes: [String] {
        Array(Set(qsos.map(\.mode))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredQSOs) { qso in
                    QSORow(qso: qso)
                }
                .onDelete(perform: deleteQSOs)
            }
            .searchable(text: $searchText, prompt: "Search callsigns or parks")
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu("Band") {
                            Button("All") { selectedBand = nil }
                            ForEach(availableBands, id: \.self) { band in
                                Button(band) { selectedBand = band }
                            }
                        }

                        Menu("Mode") {
                            Button("All") { selectedMode = nil }
                            ForEach(availableModes, id: \.self) { mode in
                                Button(mode) { selectedMode = mode }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .overlay {
                if qsos.isEmpty {
                    ContentUnavailableView(
                        "No Logs",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Import ADIF files or sync from LoFi to see your QSOs")
                    )
                }
            }
        }
    }

    private func deleteQSOs(at offsets: IndexSet) {
        for index in offsets {
            let qso = filteredQSOs[index]
            modelContext.delete(qso)
        }
    }
}

struct QSORow: View {
    let qso: QSO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)

                Spacer()

                Text(qso.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(qso.band, systemImage: "waveform")
                Label(qso.mode, systemImage: "dot.radiowaves.left.and.right")

                if let park = qso.parkReference {
                    Label(park, systemImage: "tree")
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(qso.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(qso.syncRecords) { record in
                    SyncStatusBadge(record: record)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SyncStatusBadge: View {
    let record: SyncRecord

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text(record.destinationType.displayName)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch record.status {
        case .pending: return "clock"
        case .uploaded: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var backgroundColor: Color {
        switch record.status {
        case .pending: return .orange
        case .uploaded: return .green
        case .failed: return .red
        }
    }
}
