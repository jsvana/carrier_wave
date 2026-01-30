import Foundation

// MARK: - CallsignInfoSource

/// Source of callsign information
enum CallsignInfoSource: String, Codable {
    /// From a Polo notes list (local, offline)
    case poloNotes
    /// From QRZ XML callbook API
    case qrz
}

// MARK: - CallsignInfo

/// Information about a callsign from lookup services
struct CallsignInfo: Codable, Identifiable, Equatable {
    // MARK: Lifecycle

    init(
        callsign: String,
        name: String? = nil,
        note: String? = nil,
        emoji: String? = nil,
        qth: String? = nil,
        state: String? = nil,
        country: String? = nil,
        grid: String? = nil,
        licenseClass: String? = nil,
        source: CallsignInfoSource,
        lookupDate: Date = Date()
    ) {
        self.callsign = callsign.uppercased()
        self.name = name
        self.note = note
        self.emoji = emoji
        self.qth = qth
        self.state = state
        self.country = country
        self.grid = grid
        self.licenseClass = licenseClass
        self.source = source
        self.lookupDate = lookupDate
    }

    // MARK: Internal

    /// The callsign (always uppercase)
    let callsign: String

    /// Operator name
    let name: String?

    /// Note from Polo notes list (e.g., "POTA activator")
    let note: String?

    /// Emoji from Polo notes list (e.g., "🌳")
    let emoji: String?

    /// City/QTH
    let qth: String?

    /// State/province
    let state: String?

    /// Country
    let country: String?

    /// Grid square
    let grid: String?

    /// License class (e.g., "Extra", "General")
    let licenseClass: String?

    /// Where this information came from
    let source: CallsignInfoSource

    /// When this lookup was performed
    let lookupDate: Date

    /// Unique identifier (the callsign)
    var id: String {
        callsign
    }

    /// Full location string (city, state, country)
    var fullLocation: String? {
        let parts = [qth, state, country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Whether this info is from a local source (fast, offline)
    var isLocal: Bool {
        source == .poloNotes
    }

    /// Age of this lookup in seconds
    var age: TimeInterval {
        Date().timeIntervalSince(lookupDate)
    }
}

// MARK: - CallsignInfo + Polo Notes

extension CallsignInfo {
    /// Create from a Polo notes entry
    /// - Parameters:
    ///   - callsign: The callsign
    ///   - noteText: The note text (may contain emoji and name)
    static func fromPoloNotes(callsign: String, noteText: String) -> CallsignInfo {
        // Extract emoji from the beginning of the note
        let (emoji, remainingText) = extractLeadingEmoji(from: noteText)

        // The remaining text is the name/note
        let trimmedNote = remainingText.trimmingCharacters(in: .whitespaces)

        // Try to extract just the name (first word or words before " - ")
        let name: String?
        let note: String?

        if let dashRange = trimmedNote.range(of: " - ") {
            name = String(trimmedNote[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            note = String(trimmedNote[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            // Just use the whole thing as name
            name = trimmedNote.isEmpty ? nil : trimmedNote
            note = nil
        }

        return CallsignInfo(
            callsign: callsign,
            name: name,
            note: note,
            emoji: emoji,
            source: .poloNotes
        )
    }

    /// Extract leading emoji from text
    private static func extractLeadingEmoji(from text: String) -> (
        emoji: String?, remaining: String
    ) {
        var emojiChars: [Character] = []
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char.unicodeScalars.first?.properties.isEmoji == true, char != " " {
                emojiChars.append(char)
                index = text.index(after: index)
            } else {
                break
            }
        }

        if emojiChars.isEmpty {
            return (nil, text)
        }

        let emoji = String(emojiChars)
        let remaining = String(text[index...])
        return (emoji, remaining)
    }
}
