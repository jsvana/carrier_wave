// Spot Comments Sheet
//
// Displays POTA spot comments received during an activation,
// allowing activators to see hunter feedback.

import SwiftUI

// MARK: - SpotCommentsSheet

struct SpotCommentsSheet: View {
    // MARK: Internal

    let comments: [POTASpotComment]
    let parkRef: String
    let onDismiss: () -> Void
    let onMarkRead: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if comments.isEmpty {
                    emptyView
                } else {
                    commentsList
                }
            }
            .navigationTitle("Spot Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onMarkRead()
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Comments Yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Hunters can leave comments when they spot you on POTA.")
        }
    }

    private var commentsList: some View {
        List {
            Section {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            } header: {
                Text(parkRef)
            } footer: {
                Text("Comments from hunters spotting your activation on pota.app")
            }
        }
    }

    private func commentRow(_ comment: POTASpotComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.spotter)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(.green)

                Spacer()

                Text(comment.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let commentText = comment.comments, !commentText.isEmpty {
                Text(commentText)
                    .font(.body)
            } else {
                Text("Spotted you")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if let source = comment.source, !source.isEmpty {
                Text("via \(source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SpotCommentsBadge

/// A badge showing the number of new spot comments
struct SpotCommentsBadge: View {
    let count: Int

    var body: some View {
        // swiftlint:disable:next empty_count
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .clipShape(Capsule())
        }
    }
}

// MARK: - SpotCommentsButton

/// A button that shows spot comments count and opens the sheet
struct SpotCommentsButton: View {
    // MARK: Internal

    let comments: [POTASpotComment]
    let newCount: Int
    let parkRef: String
    let onMarkRead: () -> Void

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 14))

                if newCount > 0 {
                    Text("\(newCount)")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(newCount > 0 ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                newCount > 0
                    ? Color.green.opacity(0.1)
                    : Color(.tertiarySystemBackground)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            SpotCommentsSheet(
                comments: comments,
                parkRef: parkRef,
                onDismiss: { showSheet = false },
                onMarkRead: onMarkRead
            )
        }
    }

    // MARK: Private

    @State private var showSheet = false
}

#Preview("With Comments") {
    SpotCommentsSheet(
        comments: [
            POTASpotComment(
                spotId: 1,
                spotter: "K3ABC",
                comments: "Strong signal, 599!",
                spotTime: "2025-01-15T14:30:00Z",
                source: "web"
            ),
            POTASpotComment(
                spotId: 2,
                spotter: "W1XYZ",
                comments: nil,
                spotTime: "2025-01-15T14:25:00Z",
                source: "app"
            ),
        ],
        parkRef: "K-1234",
        onDismiss: {},
        onMarkRead: {}
    )
}

#Preview("Empty") {
    SpotCommentsSheet(
        comments: [],
        parkRef: "K-1234",
        onDismiss: {},
        onMarkRead: {}
    )
}
