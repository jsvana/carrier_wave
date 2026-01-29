import SwiftUI

// MARK: - CWDetectedCallsignBar

/// Displays the most recently detected callsign with a "Use" button
struct CWDetectedCallsignBar: View {
    /// The detected callsign to display
    let callsign: DetectedCallsign?

    /// All detected callsigns for picker
    let allCallsigns: [String]

    /// Callback when user taps "Use"
    let onUse: (String) -> Void

    @State private var showingPicker = false

    var body: some View {
        if let detected = callsign {
            HStack(spacing: 12) {
                // Label
                Text("Detected callsign")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Callsign with context indicator
                HStack(spacing: 6) {
                    if allCallsigns.count > 1 {
                        // Multiple callsigns - show picker button
                        Menu {
                            ForEach(allCallsigns, id: \.self) { cs in
                                Button(cs) {
                                    onUse(cs)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(detected.callsign)
                                    .font(.title3.weight(.bold).monospaced())
                                    .foregroundStyle(callsignColor(for: detected.context))

                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(detected.callsign)
                            .font(.title3.weight(.bold).monospaced())
                            .foregroundStyle(callsignColor(for: detected.context))
                    }
                }

                // Use button
                Button {
                    onUse(detected.callsign)
                } label: {
                    Text("Use")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func callsignColor(for context: DetectedCallsign.CallsignContext) -> Color {
        switch context {
        case .cqCall:
            .blue
        case .deIdentifier:
            .green
        case .response:
            .orange
        case .unknown:
            .primary
        }
    }
}

// MARK: - CWCallsignChip

/// Small chip showing a detected callsign
struct CWCallsignChip: View {
    let callsign: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(callsign)
                .font(.caption.weight(.medium).monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CWHighlightedText

/// Displays CW text with highlighted callsigns and prosigns
struct CWHighlightedText: View {
    let elements: [CWTextElement]

    var body: some View {
        elements.reduce(Text("")) { result, element in
            result + text(for: element)
        }
    }

    private func text(for element: CWTextElement) -> Text {
        switch element {
        case let .text(str):
            Text(str)
                .foregroundColor(.primary)

        case let .callsign(str, role):
            Text(str)
                .foregroundColor(color(for: role))
                .fontWeight(.semibold)

        case let .prosign(str):
            Text(str)
                .foregroundColor(.secondary)

        case let .signalReport(str):
            Text(str)
                .foregroundColor(.orange)
                .fontWeight(.medium)
        }
    }

    private func color(for role: CWTextElement.CallsignRole) -> Color {
        switch role {
        case .caller:
            .blue
        case .callee:
            .green
        case .unknown:
            .purple
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CWDetectedCallsignBar(
            callsign: DetectedCallsign(
                callsign: "K4SWL",
                context: .deIdentifier
            ),
            allCallsigns: ["K4SWL", "N9HO"],
            onUse: { _ in }
        )
        .padding()

        CWDetectedCallsignBar(
            callsign: DetectedCallsign(
                callsign: "W1AW",
                context: .cqCall
            ),
            allCallsigns: ["W1AW"],
            onUse: { _ in }
        )
        .padding()

        HStack {
            CWCallsignChip(callsign: "K4SWL", isSelected: true, onTap: {})
            CWCallsignChip(callsign: "N9HO", isSelected: false, onTap: {})
            CWCallsignChip(callsign: "W1AW", isSelected: false, onTap: {})
        }
        .padding()

        CWHighlightedText(elements: [
            .prosign("CQ"),
            .text(" "),
            .prosign("CQ"),
            .text(" "),
            .prosign("DE"),
            .text(" "),
            .callsign("K4SWL", role: .caller),
            .text(" "),
            .callsign("K4SWL", role: .caller),
            .text(" "),
            .prosign("K"),
        ])
        .font(.body.monospaced())
        .padding()
    }
}
