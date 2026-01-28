import SwiftUI

struct StatDetailView: View {
    // MARK: Internal

    let category: StatCategoryType
    let items: [StatCategoryItem]
    let tourState: TourState

    var body: some View {
        List {
            ForEach(sortedItems) { item in
                StatItemRow(item: item)
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .miniTour(.statsDrilldown, tourState: tourState)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if category == .parks {
                        Button {
                            sortMode = .date
                        } label: {
                            Label("By Date", systemImage: sortMode == .date ? "checkmark" : "")
                        }
                    }

                    Button {
                        sortMode = .count
                    } label: {
                        Label("By Count", systemImage: sortMode == .count ? "checkmark" : "")
                    }

                    Button {
                        sortMode = .alphabetical
                    } label: {
                        Label("A-Z", systemImage: sortMode == .alphabetical ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    // MARK: Private

    private enum SortMode {
        case date
        case count
        case alphabetical
    }

    @State private var sortMode: SortMode = .date

    private var sortedItems: [StatCategoryItem] {
        switch sortMode {
        case .date:
            // Sort by date descending; fall back to count if no date
            items.sorted { lhs, rhs in
                if let lhsDate = lhs.date, let rhsDate = rhs.date {
                    return lhsDate > rhsDate
                }
                return lhs.count > rhs.count
            }
        case .count:
            items.sorted { $0.count > $1.count }
        case .alphabetical:
            items.sorted {
                $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending
            }
        }
    }
}
