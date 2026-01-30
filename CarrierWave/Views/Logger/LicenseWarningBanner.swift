// License Warning Banner
//
// Displays a warning when the user is operating outside their license privileges.

import SwiftUI

// MARK: - LicenseWarningBanner

struct LicenseWarningBanner: View {
    // MARK: Lifecycle

    init(violation: BandPlanViolation, onDismiss: (() -> Void)? = nil) {
        self.violation = violation
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let violation: BandPlanViolation
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(violation.message)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let suggestion = violation.suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: Private

    // MARK: - Styling

    private var icon: String {
        switch violation.type {
        case .noPrivileges: "exclamationmark.triangle.fill"
        case .wrongMode: "xmark.circle.fill"
        case .outOfBand: "antenna.radiowaves.left.and.right.slash"
        case .unusualFrequency: "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch violation.type {
        case .noPrivileges: .orange
        case .wrongMode: .red
        case .outOfBand: .red
        case .unusualFrequency: .blue
        }
    }

    private var backgroundColor: Color {
        switch violation.type {
        case .noPrivileges: Color.orange.opacity(0.1)
        case .wrongMode: Color.red.opacity(0.1)
        case .outOfBand: Color.red.opacity(0.1)
        case .unusualFrequency: Color.blue.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch violation.type {
        case .noPrivileges: Color.orange.opacity(0.3)
        case .wrongMode: Color.red.opacity(0.3)
        case .outOfBand: Color.red.opacity(0.3)
        case .unusualFrequency: Color.blue.opacity(0.3)
        }
    }
}

// MARK: - LicenseWarningModifier

/// View modifier to add license warning banner when needed
struct LicenseWarningModifier: ViewModifier {
    // MARK: Internal

    let frequencyMHz: Double?
    let mode: String?
    let license: LicenseClass

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if let violation, !isDismissed {
                LicenseWarningBanner(violation: violation) {
                    withAnimation {
                        isDismissed = true
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            content
        }
        .onChange(of: frequencyMHz) { _, _ in
            checkViolation()
        }
        .onChange(of: mode) { _, _ in
            checkViolation()
        }
        .onAppear {
            checkViolation()
        }
    }

    // MARK: Private

    @State private var violation: BandPlanViolation?
    @State private var isDismissed = false

    private func checkViolation() {
        guard let freq = frequencyMHz, let mode, !mode.isEmpty else {
            violation = nil
            return
        }

        let newViolation = BandPlanService.validate(
            frequencyMHz: freq,
            mode: mode,
            license: license
        )

        if newViolation?.message != violation?.message {
            withAnimation {
                violation = newViolation
                isDismissed = false
            }
        }
    }
}

extension View {
    /// Add license warning banner when operating outside privileges
    func licenseWarning(
        frequencyMHz: Double?,
        mode: String?,
        license: LicenseClass
    ) -> some View {
        modifier(
            LicenseWarningModifier(
                frequencyMHz: frequencyMHz,
                mode: mode,
                license: license
            )
        )
    }
}

// MARK: - Previews

#Preview("No Privileges") {
    LicenseWarningBanner(
        violation: BandPlanViolation(
            type: .noPrivileges,
            message: "Technician license cannot operate CW at 7.025 MHz",
            suggestion: "Requires General or higher"
        )
    )
    .padding()
}

#Preview("Wrong Mode") {
    LicenseWarningBanner(
        violation: BandPlanViolation(
            type: .wrongMode,
            message: "SSB is not allowed at 7.030 MHz",
            suggestion: "Try: CW, DATA"
        )
    )
    .padding()
}

#Preview("Out of Band") {
    LicenseWarningBanner(
        violation: BandPlanViolation(
            type: .outOfBand,
            message: "Frequency 14.400 MHz is outside amateur bands",
            suggestion: "Nearest band: 20m"
        )
    )
    .padding()
}
