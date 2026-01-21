import Foundation

struct DescriptionLookup {

    // MARK: - Entity Descriptions (Callsign Prefix -> Country)

    static func entityDescription(for prefix: String) -> String {
        let upper = prefix.uppercased()

        // Common prefixes - expand as needed
        let entities: [String: String] = [
            // USA
            "K": "United States", "W": "United States", "N": "United States", "A": "United States",
            // Europe
            "G": "England", "M": "England",
            "F": "France",
            "DL": "Germany", "DA": "Germany", "DB": "Germany", "DC": "Germany", "DD": "Germany", "DF": "Germany", "DG": "Germany", "DH": "Germany", "DI": "Germany", "DJ": "Germany", "DK": "Germany", "DM": "Germany", "DO": "Germany", "DP": "Germany", "DQ": "Germany", "DR": "Germany",
            "I": "Italy",
            "EA": "Spain", "EB": "Spain", "EC": "Spain", "ED": "Spain", "EE": "Spain", "EF": "Spain", "EG": "Spain", "EH": "Spain",
            "PA": "Netherlands", "PB": "Netherlands", "PC": "Netherlands", "PD": "Netherlands", "PE": "Netherlands", "PF": "Netherlands", "PG": "Netherlands", "PH": "Netherlands", "PI": "Netherlands",
            "ON": "Belgium",
            "OE": "Austria",
            "HB": "Switzerland", "HB9": "Switzerland",
            "SM": "Sweden",
            "LA": "Norway",
            "OZ": "Denmark",
            "OH": "Finland",
            "SP": "Poland",
            "OK": "Czech Republic",
            "OM": "Slovakia",
            "HA": "Hungary",
            "YO": "Romania",
            "LZ": "Bulgaria",
            "SV": "Greece",
            "YU": "Serbia",
            "9A": "Croatia",
            "S5": "Slovenia",
            // UK
            "GW": "Wales", "GM": "Scotland", "GI": "Northern Ireland", "GD": "Isle of Man", "GJ": "Jersey", "GU": "Guernsey",
            // Americas
            "VE": "Canada", "VA": "Canada", "VY": "Canada", "VO": "Canada",
            "XE": "Mexico", "XA": "Mexico", "XB": "Mexico", "XC": "Mexico", "XD": "Mexico", "XF": "Mexico",
            "LU": "Argentina",
            "PY": "Brazil", "PP": "Brazil", "PQ": "Brazil", "PR": "Brazil", "PS": "Brazil", "PT": "Brazil", "PU": "Brazil", "PV": "Brazil", "PW": "Brazil", "PX": "Brazil",
            "CE": "Chile",
            "HK": "Colombia",
            "HC": "Ecuador",
            "OA": "Peru",
            "YV": "Venezuela",
            // Asia/Pacific
            "JA": "Japan", "JD": "Japan", "JE": "Japan", "JF": "Japan", "JG": "Japan", "JH": "Japan", "JI": "Japan", "JJ": "Japan", "JK": "Japan", "JL": "Japan", "JM": "Japan", "JN": "Japan", "JO": "Japan", "JP": "Japan", "JQ": "Japan", "JR": "Japan", "JS": "Japan",
            "HL": "South Korea",
            "BV": "Taiwan",
            "VK": "Australia",
            "ZL": "New Zealand",
            "DU": "Philippines",
            "HS": "Thailand",
            "9M": "Malaysia",
            "9V": "Singapore",
            "YB": "Indonesia",
            "VU": "India",
            // Russia
            "UA": "Russia", "R": "Russia",
            // Africa
            "ZS": "South Africa",
            "SU": "Egypt",
            "CN": "Morocco",
            "EA8": "Canary Islands", "EA9": "Ceuta & Melilla",
            // Caribbean
            "KP4": "Puerto Rico", "KP3": "Puerto Rico", "NP4": "Puerto Rico", "WP4": "Puerto Rico",
            "KP2": "US Virgin Islands",
            "KH6": "Hawaii",
            "KL7": "Alaska",
        ]

        // Try exact match first
        if let desc = entities[upper] {
            return desc
        }

        // Try progressively shorter prefixes
        for length in stride(from: min(upper.count, 3), through: 1, by: -1) {
            let shortPrefix = String(upper.prefix(length))
            if let desc = entities[shortPrefix] {
                return desc
            }
        }

        return "Unknown"
    }

    // MARK: - Band Descriptions

    static func bandDescription(for band: String) -> String {
        let descriptions: [String: String] = [
            "160m": "1.8 MHz",
            "80m": "3.5 MHz",
            "60m": "5 MHz",
            "40m": "7 MHz",
            "30m": "10 MHz",
            "20m": "14 MHz",
            "17m": "18 MHz",
            "15m": "21 MHz",
            "12m": "24 MHz",
            "10m": "28 MHz",
            "6m": "50 MHz",
            "2m": "144 MHz",
            "70cm": "430 MHz",
            "23cm": "1.2 GHz",
        ]
        return descriptions[band.lowercased()] ?? ""
    }

    // MARK: - Mode Descriptions

    static func modeDescription(for mode: String) -> String {
        let descriptions: [String: String] = [
            "SSB": "Single Sideband Voice",
            "LSB": "Lower Sideband Voice",
            "USB": "Upper Sideband Voice",
            "CW": "Continuous Wave (Morse)",
            "FM": "Frequency Modulation Voice",
            "AM": "Amplitude Modulation Voice",
            "FT8": "Digital - FT8",
            "FT4": "Digital - FT4",
            "JS8": "Digital - JS8Call",
            "RTTY": "Radio Teletype",
            "PSK31": "Digital - PSK31",
            "SSTV": "Slow-Scan Television",
            "MFSK": "Multi-Frequency Shift Keying",
            "OLIVIA": "Digital - Olivia",
            "JT65": "Digital - JT65",
            "JT9": "Digital - JT9",
            "WSPR": "Weak Signal Propagation Reporter",
        ]
        return descriptions[mode.uppercased()] ?? ""
    }

    // MARK: - Grid Descriptions

    static func gridDescription(for grid: String) -> String {
        // Grid squares are geographic - could expand to show region names
        // For now, return empty (grid itself is descriptive)
        return ""
    }

    // MARK: - Park Descriptions

    static func parkDescription(for parkReference: String) -> String {
        // Park names would come from QSO data or POTA API
        // For now, return empty
        return ""
    }
}
