import Foundation

// MARK: - DetectedCallsign

/// A callsign detected in the transcript with context
struct DetectedCallsign: Identifiable, Equatable {
    let id: UUID
    let callsign: String
    let context: CallsignContext
    let timestamp: Date

    init(id: UUID = UUID(), callsign: String, context: CallsignContext, timestamp: Date = Date()) {
        self.id = id
        self.callsign = callsign
        self.context = context
        self.timestamp = timestamp
    }

    /// Context in which the callsign was detected
    enum CallsignContext: Equatable {
        case cqCall // Station calling CQ
        case deIdentifier // Station identifying with DE
        case response // Station responding
        case unknown // Callsign without clear context
    }
}

// MARK: - CWTextElement

/// A segment of decoded CW text with optional highlighting
enum CWTextElement: Identifiable, Equatable {
    case text(String)
    case callsign(String, role: CallsignRole)
    case prosign(String)
    case signalReport(String)

    var id: String {
        switch self {
        case let .text(str): "text-\(str)"
        case let .callsign(str, _): "call-\(str)"
        case let .prosign(str): "pro-\(str)"
        case let .signalReport(str): "rst-\(str)"
        }
    }

    /// Role of the callsign in the QSO
    enum CallsignRole: Equatable {
        case caller // Station calling (after CQ or before DE)
        case callee // Station being called (after DE)
        case unknown
    }
}

// MARK: - CallsignDetector

/// Detects and extracts callsigns from decoded CW text
struct CallsignDetector {
    // MARK: - Callsign Pattern

    /// International amateur radio callsign pattern
    /// Format: Prefix (1-3 alphanumeric) + Number + Suffix (1-4 letters)
    /// Examples: W1AW, VK2ABC, JA1XYZ, 9A2AA, 3DA0RS
    private static let callsignPattern = #"[A-Z0-9]{1,3}[0-9][A-Z]{1,4}"#

    /// Signal report pattern (RST format)
    private static let signalReportPattern = #"\b[1-5][1-9][1-9]?\b"#

    /// Common prosigns to identify
    private static let prosigns = Set(["CQ", "DE", "K", "KN", "BK", "SK", "AR", "BT", "AS", "R", "TU", "QSL"])

    /// Compiled regex for callsigns
    private static let callsignRegex = try? NSRegularExpression(
        pattern: callsignPattern,
        options: [.caseInsensitive]
    )

    /// Compiled regex for signal reports
    private static let rstRegex = try? NSRegularExpression(
        pattern: signalReportPattern,
        options: []
    )

    // MARK: - Public API

    /// Extract all callsigns from text
    /// - Parameter text: Decoded CW text
    /// - Returns: Array of unique callsigns found
    static func extractCallsigns(from text: String) -> [String] {
        guard let regex = callsignRegex else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text.uppercased(), options: [], range: range)

        var callsigns: [String] = []
        var seen = Set<String>()

        for match in matches {
            if let swiftRange = Range(match.range, in: text.uppercased()) {
                let callsign = String(text.uppercased()[swiftRange])
                // Filter out false positives (too short, common words)
                if isValidCallsign(callsign), !seen.contains(callsign) {
                    callsigns.append(callsign)
                    seen.insert(callsign)
                }
            }
        }

        return callsigns
    }

    /// Detect the most likely "other station" callsign from transcript
    /// Uses context clues like CQ, DE, and position to determine
    /// - Parameter entries: Transcript entries
    /// - Returns: Most likely callsign to log, if found
    static func detectPrimaryCallsign(from entries: [CWTranscriptEntry]) -> DetectedCallsign? {
        let fullText = entries.map(\.text).joined(separator: " ").uppercased()
        let words = fullText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var candidates: [DetectedCallsign] = []

        for (index, word) in words.enumerated() {
            guard isValidCallsign(word) else { continue }

            // Check context
            let context = determineContext(for: word, at: index, in: words)
            let candidate = DetectedCallsign(callsign: word, context: context)
            candidates.append(candidate)
        }

        // Prioritize by context: DE identifier > CQ call > response > unknown
        let priority: [DetectedCallsign.CallsignContext] = [.deIdentifier, .cqCall, .response, .unknown]

        for targetContext in priority {
            if let match = candidates.last(where: { $0.context == targetContext }) {
                return match
            }
        }

        return candidates.last
    }

    /// Parse text into highlighted elements
    /// - Parameter text: Raw decoded CW text
    /// - Returns: Array of text elements with highlighting info
    static func parseElements(from text: String) -> [CWTextElement] {
        let uppercased = text.uppercased()
        var elements: [CWTextElement] = []
        var currentIndex = uppercased.startIndex

        // Find all callsigns and their ranges
        guard let regex = callsignRegex else {
            return [.text(text)]
        }

        let nsRange = NSRange(uppercased.startIndex..., in: uppercased)
        let matches = regex.matches(in: uppercased, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range, in: uppercased) else { continue }

            let callsign = String(uppercased[range])
            guard isValidCallsign(callsign) else { continue }

            // Add text before this callsign
            if currentIndex < range.lowerBound {
                let beforeText = String(uppercased[currentIndex ..< range.lowerBound])
                let beforeElements = parseNonCallsignText(beforeText)
                elements.append(contentsOf: beforeElements)
            }

            // Determine callsign role from surrounding context
            let role = determineRole(for: callsign, in: uppercased, at: range)
            elements.append(.callsign(callsign, role: role))

            currentIndex = range.upperBound
        }

        // Add remaining text
        if currentIndex < uppercased.endIndex {
            let remainingText = String(uppercased[currentIndex...])
            let remainingElements = parseNonCallsignText(remainingText)
            elements.append(contentsOf: remainingElements)
        }

        return elements.isEmpty ? [.text(text)] : elements
    }

    // MARK: - Private Helpers

    /// Validate that a string is a plausible callsign
    private static func isValidCallsign(_ candidate: String) -> Bool {
        // Must be at least 4 characters (e.g., W1AW)
        guard candidate.count >= 4 else { return false }

        // Must not be all numbers
        guard candidate.contains(where: { $0.isLetter }) else { return false }

        // Must contain at least one number
        guard candidate.contains(where: { $0.isNumber }) else { return false }

        // Filter out common false positives
        let falsePositives = Set(["1ST", "2ND", "3RD", "4TH", "5TH", "73S", "88S", "599S"])
        if falsePositives.contains(candidate) { return false }

        return true
    }

    /// Determine the context of a callsign based on surrounding words
    private static func determineContext(
        for callsign: String,
        at index: Int,
        in words: [String]
    ) -> DetectedCallsign.CallsignContext {
        // Check if preceded by DE
        if index > 0, words[index - 1] == "DE" {
            return .deIdentifier
        }

        // Check if part of CQ sequence
        if index > 0 {
            let preceding = words[max(0, index - 3) ..< index]
            if preceding.contains("CQ") {
                return .cqCall
            }
        }

        // Check if followed by DE (this is the station being called)
        if index < words.count - 1, words[index + 1] == "DE" {
            return .response
        }

        return .unknown
    }

    /// Determine the role of a callsign based on context
    private static func determineRole(
        for callsign: String,
        in text: String,
        at range: Range<String.Index>
    ) -> CWTextElement.CallsignRole {
        // Check what comes before
        let beforeStart = text.index(range.lowerBound, offsetBy: -4, limitedBy: text.startIndex) ?? text.startIndex
        let beforeText = String(text[beforeStart ..< range.lowerBound]).trimmingCharacters(in: .whitespaces)

        if beforeText.hasSuffix("DE") {
            return .callee
        }

        if beforeText.contains("CQ") {
            return .caller
        }

        // Check what comes after
        if range.upperBound < text.endIndex {
            let afterEnd = text.index(range.upperBound, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
            let afterText = String(text[range.upperBound ..< afterEnd]).trimmingCharacters(in: .whitespaces)

            if afterText.hasPrefix("DE") {
                return .caller
            }
        }

        return .unknown
    }

    /// Parse non-callsign text into prosigns, RST, and plain text
    private static func parseNonCallsignText(_ text: String) -> [CWTextElement] {
        var elements: [CWTextElement] = []
        let words = text.components(separatedBy: .whitespaces)

        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if prosigns.contains(trimmed) {
                elements.append(.prosign(trimmed))
            } else if isSignalReport(trimmed) {
                elements.append(.signalReport(trimmed))
            } else {
                // Add as plain text with space
                if case let .text(existing) = elements.last {
                    elements.removeLast()
                    elements.append(.text(existing + " " + trimmed))
                } else {
                    elements.append(.text(trimmed))
                }
            }
        }

        return elements
    }

    /// Check if text is a signal report (RST format)
    private static func isSignalReport(_ text: String) -> Bool {
        guard text.count == 3 || text.count == 2 else { return false }
        guard text.allSatisfy({ $0.isNumber }) else { return false }

        // RST: R=1-5, S=1-9, T=1-9 (optional)
        let chars = Array(text)
        guard let r = chars[0].wholeNumberValue, r >= 1, r <= 5 else { return false }
        guard let s = chars[1].wholeNumberValue, s >= 1, s <= 9 else { return false }
        if chars.count == 3 {
            guard let t = chars[2].wholeNumberValue, t >= 1, t <= 9 else { return false }
        }

        return true
    }
}
