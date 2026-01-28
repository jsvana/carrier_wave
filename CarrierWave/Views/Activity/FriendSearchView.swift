import SwiftUI

// MARK: - FriendSearchView

/// Placeholder view for searching and adding friends.
/// This will be fully implemented in Task 4.3.
struct FriendSearchView: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "magnifyingglass",
            description: Text("Friend search will be implemented soon")
        )
        .navigationTitle("Add Friend")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FriendSearchView()
    }
}
