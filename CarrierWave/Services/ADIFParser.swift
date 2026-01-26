//
//  ADIFParser.swift
//  CarrierWave
//
//  Created by Jay Vana on 1/20/26.
//

import Foundation

// MARK: - ADIFRecord

struct ADIFRecord {
    var callsign: String
    var band: String
    var mode: String
    var frequency: Double?
    var qsoDate: String? // YYYYMMDD
    var timeOn: String? // HHMM or HHMMSS
    var rstSent: String?
    var rstReceived: String?
    var myCallsign: String?
    var myGridsquare: String?
    var gridsquare: String? // Their grid
    var sigInfo: String? // Their park reference (hunter contacts)
    var mySigInfo: String? // My park reference (activations)
    var comment: String?
    var rawADIF: String

    var timestamp: Date? {
        guard let dateStr = qsoDate else {
            return nil
        }
        let timeStr = timeOn ?? "0000"

        let formatter = DateFormatter()
        formatter.dateFormat = timeStr.count == 6 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return formatter.date(from: dateStr + timeStr)
    }
}

// MARK: - ADIFParser

struct ADIFParser {
    // MARK: Internal

    func parse(_ content: String) throws -> [ADIFRecord] {
        var records: [ADIFRecord] = []

        // Find header end if present
        let workingContent: String =
            if let headerEnd = content.range(of: "<eoh>", options: .caseInsensitive) {
                String(content[headerEnd.upperBound...])
            } else {
                content
            }

        // Split by <eor> (end of record)
        let rawRecords = workingContent.split(separator: "<eor>", omittingEmptySubsequences: true)
            .map { $0.split(separator: "<EOR>", omittingEmptySubsequences: true) }
            .flatMap { $0 }
            .map { String($0) }

        for rawRecord in rawRecords {
            let trimmed = rawRecord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let fields = parseFields(from: trimmed)
            guard let callsign = fields["call"],
                  let band = fields["band"],
                  let mode = fields["mode"]
            else {
                continue // Skip records missing required fields
            }

            let record = ADIFRecord(
                callsign: callsign.uppercased(),
                band: band.lowercased(),
                mode: mode.uppercased(),
                frequency: fields["freq"].flatMap { Double($0) },
                qsoDate: fields["qso_date"],
                timeOn: fields["time_on"],
                rstSent: fields["rst_sent"],
                rstReceived: fields["rst_rcvd"],
                myCallsign: fields["station_callsign"] ?? fields["operator"],
                myGridsquare: fields["my_gridsquare"],
                gridsquare: fields["gridsquare"],
                sigInfo: fields["sig_info"] ?? fields["pota_ref"],
                mySigInfo: fields["my_sig_info"],
                comment: fields["comment"] ?? fields["notes"],
                rawADIF: "<" + trimmed + "<eor>"
            )

            records.append(record)
        }

        return records
    }

    // MARK: Private

    private func parseFields(from record: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Pattern: <fieldname:length>value or <fieldname:length:type>value
        let pattern = #"<(\w+):(\d+)(?::\w)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else {
            return fields
        }

        let nsString = record as NSString
        let matches = regex.matches(
            in: record, range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            guard match.numberOfRanges >= 3 else {
                continue
            }

            let fieldName = nsString.substring(with: match.range(at: 1)).lowercased()
            let lengthStr = nsString.substring(with: match.range(at: 2))
            guard let length = Int(lengthStr) else {
                continue
            }

            let valueStart = match.range.location + match.range.length
            guard valueStart + length <= nsString.length else {
                continue
            }

            let value = nsString.substring(with: NSRange(location: valueStart, length: length))
            fields[fieldName] = value.trimmingCharacters(in: .whitespaces)
        }

        return fields
    }
}
