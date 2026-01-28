import SwiftData
import SwiftUI

// MARK: - FriendsListView

struct FriendsListView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if friendships.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2",
                    description: Text("Search for friends by their callsign to connect and see their activity")
                )
            } else {
                friendsList
            }
        }
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    FriendSearchView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Friendship.friendCallsign)
    private var friendships: [Friendship]

    private var acceptedFriends: [Friendship] {
        friendships.filter(\.isAccepted)
    }

    private var incomingRequests: [Friendship] {
        friendships.filter { $0.isPending && !$0.isOutgoing }
    }

    private var outgoingRequests: [Friendship] {
        friendships.filter { $0.isPending && $0.isOutgoing }
    }

    @ViewBuilder
    private var friendsList: some View {
        List {
            if !incomingRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(incomingRequests) { friendship in
                        IncomingRequestRow(
                            friendship: friendship,
                            onAccept: { acceptRequest(friendship) },
                            onDecline: { declineRequest(friendship) }
                        )
                    }
                }
            }

            if !outgoingRequests.isEmpty {
                Section("Sent Requests") {
                    ForEach(outgoingRequests) { friendship in
                        OutgoingRequestRow(friendship: friendship)
                    }
                }
            }

            if !acceptedFriends.isEmpty {
                Section("Friends") {
                    ForEach(acceptedFriends) { friendship in
                        FriendRow(friendship: friendship)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            removeFriend(acceptedFriends[index])
                        }
                    }
                }
            }
        }
    }

    private func acceptRequest(_ friendship: Friendship) {
        // Will call FriendsSyncService
    }

    private func declineRequest(_ friendship: Friendship) {
        // Will call FriendsSyncService
    }

    private func removeFriend(_ friendship: Friendship) {
        // Will call FriendsSyncService
    }
}

// MARK: - IncomingRequestRow

private struct IncomingRequestRow: View {
    let friendship: Friendship
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            Button("Accept") {
                onAccept()
            }
            .buttonStyle(.borderedProminent)

            Button("Decline") {
                onDecline()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}

// MARK: - OutgoingRequestRow

private struct OutgoingRequestRow: View {
    let friendship: Friendship

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            Text("Pending...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FriendRow

private struct FriendRow: View {
    let friendship: Friendship

    var body: some View {
        Text(friendship.friendCallsign)
            .font(.headline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FriendsListView()
    }
    .modelContainer(for: [Friendship.self], inMemory: true)
}
