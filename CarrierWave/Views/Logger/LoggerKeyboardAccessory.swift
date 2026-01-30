// Logger Keyboard Accessory
//
// Provides a number row and quick command buttons above the keyboard.

import SwiftUI

// MARK: - LoggerKeyboardAccessory

struct LoggerKeyboardAccessory: View {
    // MARK: Internal

    @Binding var text: String

    let onCommand: (LoggerCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Number row
            HStack(spacing: 4) {
                ForEach(1 ... 9, id: \.self) { num in
                    numberButton(String(num))
                }
                numberButton("0")
                numberButton(".")
                numberButton("/")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)

            Divider()

            // Quick command buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    commandButton("RBN", icon: "dot.radiowaves.up.forward", command: .rbn)
                    commandButton("SOLAR", icon: "sun.max", command: .solar)
                    commandButton("WX", icon: "cloud.sun", command: .weather)
                    commandButton("SPOT", icon: "mappin.and.ellipse", command: .spot)
                    commandButton("HELP", icon: "questionmark.circle", command: .help)

                    Divider()
                        .frame(height: 24)

                    // Common frequencies
                    freqButton("7.030", label: "40m CW")
                    freqButton("14.060", label: "20m CW")
                    freqButton("7.185", label: "40m SSB")
                    freqButton("14.285", label: "20m SSB")
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Private

    // MARK: - Button Builders

    private func numberButton(_ char: String) -> some View {
        Button {
            text.append(char)
        } label: {
            Text(char)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func commandButton(_ label: String, icon: String, command: LoggerCommand) -> some View {
        Button {
            onCommand(command)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.15))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func freqButton(_ freq: String, label: String) -> some View {
        Button {
            text = freq
        } label: {
            VStack(spacing: 2) {
                Text(freq)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - KeyboardAccessoryModifier

struct KeyboardAccessoryModifier: ViewModifier {
    @Binding var text: String

    let onCommand: (LoggerCommand) -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // Number row for frequency entry
                    Button("1") { text.append("1") }
                    Button("2") { text.append("2") }
                    Button("3") { text.append("3") }
                    Button("4") { text.append("4") }
                    Button("5") { text.append("5") }
                    Button("6") { text.append("6") }
                    Button("7") { text.append("7") }
                    Button("8") { text.append("8") }
                    Button("9") { text.append("9") }
                    Button("0") { text.append("0") }
                    Button(".") { text.append(".") }
                }
            }
    }
}

extension View {
    func loggerKeyboardAccessory(
        text: Binding<String>,
        onCommand: @escaping (LoggerCommand) -> Void
    ) -> some View {
        modifier(KeyboardAccessoryModifier(text: text, onCommand: onCommand))
    }
}

#Preview {
    VStack {
        Spacer()
        LoggerKeyboardAccessory(text: .constant("")) { _ in }
    }
}
