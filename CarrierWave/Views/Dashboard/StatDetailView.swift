import SwiftUI

struct StatDetailView: View {
    // MARK: Internal

    let category: StatCategoryType
    let items: [StatCategoryItem]

    var body: some View {
        List {
            ForEach(sortedItems) { item in
                StatItemRow(item: item)
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sortByCount = true
                    } label: {
                        Label("By Count", systemImage: sortByCount ? "checkmark" : "")
                    }

                    Button {
                        sortByCount = false
                    } label: {
                        Label("A-Z", systemImage: sortByCount ? "" : "checkmark")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    // MARK: Private

    @State private var sortByCount = true

    private var sortedItems: [StatCategoryItem] {
        if sortByCount {
            items.sorted { $0.count > $1.count }
        } else {
            items.sorted { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
        }
    }
}
