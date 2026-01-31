import SwiftUI

// MARK: - DashboardView Stats Grid Extension

extension DashboardView {
    var statsGrid: some View {
        LazyVGrid(columns: statsGridColumns, spacing: 12) {
            Button {
                selectedTab = .logs
            } label: {
                StatBox(
                    title: "QSOs",
                    value: "\(stats.totalQSOs)",
                    icon: "antenna.radiowaves.left.and.right"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatDetailView(
                    category: .qsls, items: stats.items(for: .qsls), tourState: tourState
                )
            } label: {
                StatBox(title: "QSLs", value: "\(stats.confirmedQSLs)", icon: "checkmark.seal")
            }
            .buttonStyle(.plain)

            if lotwIsConfigured {
                NavigationLink {
                    StatDetailView(
                        category: .entities, items: stats.items(for: .entities),
                        tourState: tourState
                    )
                } label: {
                    StatBox(title: "DXCC Entities", value: "\(stats.uniqueEntities)", icon: "globe")
                }
                .buttonStyle(.plain)
            } else {
                StatBox(title: "DXCC Entities", value: "--", icon: "globe")
                    .opacity(0.5)
            }

            NavigationLink {
                StatDetailView(
                    category: .grids, items: stats.items(for: .grids), tourState: tourState
                )
            } label: {
                StatBox(title: "Grids", value: "\(stats.uniqueGrids)", icon: "square.grid.3x3")
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatDetailView(
                    category: .bands, items: stats.items(for: .bands), tourState: tourState
                )
            } label: {
                StatBox(title: "Bands", value: "\(stats.uniqueBands)", icon: "waveform")
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatDetailView(
                    category: .parks, items: stats.items(for: .parks), tourState: tourState
                )
            } label: {
                ActivationsStatBox(successful: stats.successfulActivations)
            }
            .buttonStyle(.plain)
        }
    }

    func streakRow(title: String, streak: StreakInfo) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            StreakStatBox(streak: streak)
        }
    }
}
