import Foundation

// MARK: - MorseCode

/// Morse code lookup table and utilities
enum MorseCode {
    // MARK: - Morse to Character Mapping

    /// Standard International Morse Code mapping
    /// Key: morse pattern (. = dit, - = dah)
    /// Value: decoded character
    static let morseToChar: [String: String] = [
        // Letters
        ".-": "A",
        "-...": "B",
        "-.-.": "C",
        "-..": "D",
        ".": "E",
        "..-.": "F",
        "--.": "G",
        "....": "H",
        "..": "I",
        ".---": "J",
        "-.-": "K",
        ".-..": "L",
        "--": "M",
        "-.": "N",
        "---": "O",
        ".--.": "P",
        "--.-": "Q",
        ".-.": "R",
        "...": "S",
        "-": "T",
        "..-": "U",
        "...-": "V",
        ".--": "W",
        "-..-": "X",
        "-.--": "Y",
        "--..": "Z",

        // Numbers
        ".----": "1",
        "..---": "2",
        "...--": "3",
        "....-": "4",
        ".....": "5",
        "-....": "6",
        "--...": "7",
        "---..": "8",
        "----.": "9",
        "-----": "0",

        // Punctuation
        ".-.-.-": ".",
        "--..--": ",",
        "..--..": "?",
        ".----.": "'",
        "-.-.--": "!",
        "-..-.": "/",
        "-.--.": "(",
        "-.--.-": ")",
        ".-...": "&",
        "---...": ":",
        "-.-.-.": ";",
        "-...-": "=",
        ".-.-.": "+",
        "-....-": "-",
        "..--.-": "_",
        ".-..-.": "\"",
        "...-..-": "$",
        ".--.-.": "@",

        // Prosigns (procedural signals) - common in amateur radio
        "-.-.-": "<CT>", // Start copying / attention
        ".-.-": "<AA>", // New line / new section
        "...-.-": "<SK>", // End of contact
        "-...-": "<BT>", // Break / pause
        ".-...": "<AS>", // Wait
        "...-.": "<SN>", // Understood / verified
        "-.-": "<K>", // Go ahead / over (same as K letter)
        "-.--.": "<KN>", // Go ahead, named station only
        "-.--.-": "<KN>", // Alternative KN
        "...-.-": "<VA>", // End of work (same as SK)
        "........": "<HH>", // Error / correction
    ]

    /// Character to Morse mapping (reverse of morseToChar)
    static let charToMorse: [String: String] = {
        var result: [String: String] = [:]
        for (morse, char) in morseToChar {
            // Skip prosigns for reverse lookup (use letter form)
            if !char.hasPrefix("<") {
                result[char] = morse
            }
        }
        return result
    }()

    // MARK: - Timing Constants

    /// Standard Morse timing relationships
    /// All times are relative to one "unit" (the length of a dit)
    enum Timing {
        /// Dit length = 1 unit
        static let ditUnits: Double = 1.0

        /// Dah length = 3 units
        static let dahUnits: Double = 3.0

        /// Inter-element gap (within character) = 1 unit
        static let elementGapUnits: Double = 1.0

        /// Inter-character gap = 3 units
        static let charGapUnits: Double = 3.0

        /// Inter-word gap = 7 units
        static let wordGapUnits: Double = 7.0

        /// Calculate unit duration in seconds from WPM
        /// PARIS standard: "PARIS" = 50 units, so at W WPM, unit = 1.2/W seconds
        static func unitDuration(forWPM wpm: Int) -> TimeInterval {
            1.2 / Double(wpm)
        }

        /// Calculate WPM from unit duration
        static func wpm(fromUnitDuration duration: TimeInterval) -> Int {
            guard duration > 0 else { return 20 }
            return max(5, min(60, Int(1.2 / duration)))
        }
    }

    // MARK: - Decoding

    /// Decode a morse pattern to a character
    /// - Parameter pattern: Morse pattern string (e.g., ".-" for A)
    /// - Returns: Decoded character or nil if not found
    static func decode(_ pattern: String) -> String? {
        morseToChar[pattern]
    }

    /// Encode a character to morse
    /// - Parameter char: Character to encode
    /// - Returns: Morse pattern or nil if not encodable
    static func encode(_ char: Character) -> String? {
        charToMorse[String(char).uppercased()]
    }

    // MARK: - Common QSO Abbreviations

    /// Common CW abbreviations used in amateur radio QSOs
    static let abbreviations: [String: String] = [
        "CQ": "Calling any station",
        "DE": "From (this is)",
        "K": "Go ahead / over",
        "KN": "Go ahead, named station only",
        "BK": "Break (back to you)",
        "SK": "End of contact",
        "73": "Best regards",
        "88": "Love and kisses",
        "RST": "Readability, Strength, Tone",
        "UR": "Your / You are",
        "R": "Received / Roger",
        "QTH": "Location",
        "QSL": "Confirmation / I confirm",
        "QRZ": "Who is calling?",
        "QRS": "Send slower",
        "QRQ": "Send faster",
        "QRM": "Interference",
        "QRN": "Static / noise",
        "QSB": "Fading",
        "QSY": "Change frequency",
        "AGN": "Again",
        "ANT": "Antenna",
        "BT": "Break / separator",
        "CFM": "Confirm",
        "CL": "Closing station",
        "CUL": "See you later",
        "FB": "Fine business (great)",
        "FER": "For",
        "GA": "Good afternoon / Go ahead",
        "GE": "Good evening",
        "GM": "Good morning",
        "GN": "Good night",
        "HI": "Laughter",
        "HR": "Here",
        "HW": "How",
        "NR": "Number",
        "OM": "Old man (male operator)",
        "OP": "Operator",
        "PSE": "Please",
        "PWR": "Power",
        "RIG": "Radio equipment",
        "RPT": "Repeat",
        "SIG": "Signal",
        "TNX": "Thanks",
        "TU": "Thank you",
        "VY": "Very",
        "WX": "Weather",
        "XYL": "Wife",
        "YL": "Young lady (female operator)",
    ]
}
