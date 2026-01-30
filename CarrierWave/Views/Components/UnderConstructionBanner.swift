// Under Construction Banner
//
// A dismissible warning banner for features still in development.

import SwiftUI

struct UnderConstructionBanner: View {
    // MARK: Internal

    var body: some View {
        if isVisible, !hideBanner {
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Under Construction")
                        .font(.subheadline.weight(.semibold))

                    Text("This feature is still in development")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        withAnimation {
                            isVisible = false
                        }
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }

                    Button {
                        hideBanner = true
                    } label: {
                        Label("Don't show again", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Private

    @AppStorage("hideUnderConstructionBanner") private var hideBanner = false
    @State private var isVisible = true
}

#Preview {
    VStack {
        UnderConstructionBanner()
            .padding()
        Spacer()
    }
}
