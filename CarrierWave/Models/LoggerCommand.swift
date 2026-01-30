// swiftlint:disable function_body_length
import Foundation

// MARK: - LoggerCommand

/// Commands that can be entered in the logger input field
enum LoggerCommand: Equatable {
    /// Change frequency (e.g., "14.060" or "FREQ 14.060")
    case frequency(Double)

    /// Change mode (e.g., "MODE CW")
    case mode(String)

    /// Self-spot to POTA
    case spot

    /// Show RBN spots panel
    case rbn

    /// Show solar conditions panel
    case solar

    /// Show weather panel
    case weather

    /// Show help
    case help

    // MARK: Internal

    /// Help text listing all available commands
    static var helpText: String {
        """
        Available Commands:

        FREQ <MHz>  - Set frequency (e.g., 14.060)
        MODE <mode> - Set mode (CW, SSB, FT8, etc.)
        SPOT        - Self-spot to POTA
        RBN         - Show RBN spots
        SOLAR       - Show solar conditions
        WEATHER     - Show weather (or WX)
        HELP        - Show this help (or ?)

        You can also just type a frequency like "14.060"
        """
    }

    /// Description of the command for display
    var description: String {
        switch self {
        case let .frequency(freq):
            String(format: "Set frequency to %.3f MHz", freq)
        case let .mode(mode):
            "Set mode to \(mode)"
        case .spot:
            "Self-spot to POTA"
        case .rbn:
            "Show RBN spots"
        case .solar:
            "Show solar conditions"
        case .weather:
            "Show weather"
        case .help:
            "Show available commands"
        }
    }

    /// Icon for the command
    var icon: String {
        switch self {
        case .frequency:
            "antenna.radiowaves.left.and.right"
        case .mode:
            "waveform"
        case .spot:
            "mappin.and.ellipse"
        case .rbn:
            "dot.radiowaves.up.forward"
        case .solar:
            "sun.max"
        case .weather:
            "cloud.sun"
        case .help:
            "questionmark.circle"
        }
    }

    /// Parse input string to command
    /// Returns nil if input is not a command (treat as callsign)
    static func parse(_ input: String) -> LoggerCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()

        // Check for frequency (number only, between 1.8 and 450 MHz)
        if let freq = Double(trimmed), freq >= 1.8, freq <= 450.0 {
            return .frequency(freq)
        }

        // Check for FREQ command
        if upper.hasPrefix("FREQ ") || upper.hasPrefix("FREQ\t") {
            let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let freq = Double(value), freq >= 1.8, freq <= 450.0 {
                return .frequency(freq)
            }
            return nil
        }

        // Check for MODE command
        if upper.hasPrefix("MODE ") || upper.hasPrefix("MODE\t") {
            let mode = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                .uppercased()
            if Self.validModes.contains(mode) {
                return .mode(mode)
            }
            return nil
        }

        // Single-word commands
        switch upper {
        case "SPOT":
            return .spot
        case "RBN":
            return .rbn
        case "SOLAR":
            return .solar
        case "WEATHER",
             "WX":
            return .weather
        case "HELP",
             "?":
            return .help
        default:
            return nil
        }
    }

    // MARK: Private

    /// Valid mode strings
    private static let validModes: Set<String> = [
        "CW",
        "SSB",
        "USB",
        "LSB",
        "AM",
        "FM",
        "FT8",
        "FT4",
        "RTTY",
        "PSK31",
        "PSK",
        "DIGITAL",
        "DATA",
        "SSTV",
        "JT65",
        "JT9",
        "WSPR",
    ]
}

// MARK: - Command Suggestions

extension LoggerCommand {
    /// Get command suggestions for autocomplete
    static func suggestions(for input: String) -> [CommandSuggestion] {
        let upper = input.uppercased()

        var suggestions: [CommandSuggestion] = []

        // Frequency suggestions
        if upper.hasPrefix("FREQ") || upper.hasPrefix("F") {
            suggestions.append(
                CommandSuggestion(
                    command: "FREQ 14.060",
                    description: "Set frequency",
                    icon: "antenna.radiowaves.left.and.right"
                )
            )
        }

        // Mode suggestions
        if upper.hasPrefix("MODE") || upper.hasPrefix("M") {
            suggestions.append(
                CommandSuggestion(
                    command: "MODE CW",
                    description: "Set mode to CW",
                    icon: "waveform"
                )
            )
            suggestions.append(
                CommandSuggestion(
                    command: "MODE SSB",
                    description: "Set mode to SSB",
                    icon: "waveform"
                )
            )
        }

        // SPOT
        if upper.hasPrefix("SP") || upper == "S" {
            suggestions.append(
                CommandSuggestion(
                    command: "SPOT",
                    description: "Self-spot to POTA",
                    icon: "mappin.and.ellipse"
                )
            )
        }

        // RBN
        if upper.hasPrefix("RB") || upper == "R" {
            suggestions.append(
                CommandSuggestion(
                    command: "RBN",
                    description: "Show RBN spots",
                    icon: "dot.radiowaves.up.forward"
                )
            )
        }

        // SOLAR
        if upper.hasPrefix("SO") {
            suggestions.append(
                CommandSuggestion(
                    command: "SOLAR",
                    description: "Show solar conditions",
                    icon: "sun.max"
                )
            )
        }

        // WEATHER
        if upper.hasPrefix("WE") || upper.hasPrefix("WX") || upper == "W" {
            suggestions.append(
                CommandSuggestion(
                    command: "WEATHER",
                    description: "Show weather",
                    icon: "cloud.sun"
                )
            )
        }

        // HELP
        if upper.hasPrefix("HE") || upper == "H" || upper == "?" {
            suggestions.append(
                CommandSuggestion(
                    command: "HELP",
                    description: "Show available commands",
                    icon: "questionmark.circle"
                )
            )
        }

        return suggestions
    }
}

// MARK: - CommandSuggestion

/// A command suggestion for autocomplete
struct CommandSuggestion: Identifiable {
    let id = UUID()
    let command: String
    let description: String
    let icon: String
}
