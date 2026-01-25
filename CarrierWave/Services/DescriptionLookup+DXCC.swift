import Foundation

// MARK: - DescriptionLookup DXCC Data

extension DescriptionLookup {
    /// Look up DXCC entity for a callsign
    /// Returns entity number and name, or nil if not found
    static func dxccEntity(for callsign: String) -> DXCCEntity? {
        let upper = callsign.uppercased()
        // Remove any suffix after /
        let base = upper.components(separatedBy: "/").first ?? upper

        // Check prefixes from longest to shortest to handle special cases
        // like KH6 (Hawaii) before K (USA)
        for (prefixes, entity) in dxccEntities {
            for prefix in prefixes.sorted(by: { $0.count > $1.count }) where base.hasPrefix(prefix) {
                return entity
            }
        }

        // Try matching just first 1-3 characters
        for length in [3, 2, 1] {
            guard base.count >= length else {
                continue
            }
            let shortPrefix = String(base.prefix(length))
            for (prefixes, entity) in dxccEntities where prefixes.contains(shortPrefix) {
                return entity
            }
        }

        return nil
    }

    /// Official DXCC entities with their numbers
    /// Note: Prefixes are checked longest-first to handle special cases like KH6 before K
    static let dxccEntities: [(prefixes: [String], entity: DXCCEntity)] = [
        // US Territories (must check before general US prefixes)
        (["KH0", "AH0", "NH0", "WH0"], DXCCEntity(number: 166, name: "Mariana Islands")),
        (["KH1", "AH1", "NH1", "WH1"], DXCCEntity(number: 35, name: "Baker & Howland Islands")),
        (["KH2", "AH2", "NH2", "WH2"], DXCCEntity(number: 103, name: "Guam")),
        (["KH3", "AH3", "NH3", "WH3"], DXCCEntity(number: 123, name: "Johnston Island")),
        (["KH4", "AH4", "NH4", "WH4"], DXCCEntity(number: 174, name: "Midway Island")),
        (["KH5", "AH5", "NH5", "WH5"], DXCCEntity(number: 197, name: "Palmyra & Jarvis Islands")),
        (["KH6", "KH7", "AH6", "AH7", "NH6", "NH7", "WH6", "WH7"], DXCCEntity(number: 110, name: "Hawaii")),
        (["KH8", "AH8", "NH8", "WH8"], DXCCEntity(number: 9, name: "American Samoa")),
        (["KH9", "AH9", "NH9", "WH9"], DXCCEntity(number: 515, name: "Wake Island")),
        (["KL7", "AL7", "NL7", "WL7", "KL", "AL", "NL", "WL"], DXCCEntity(number: 6, name: "Alaska")),
        (["KP1", "NP1", "WP1"], DXCCEntity(number: 182, name: "Navassa Island")),
        (["KP2", "NP2", "WP2"], DXCCEntity(number: 285, name: "US Virgin Islands")),
        (["KP3", "KP4", "NP3", "NP4", "WP3", "WP4"], DXCCEntity(number: 202, name: "Puerto Rico")),
        (["KP5", "NP5", "WP5"], DXCCEntity(number: 43, name: "Desecheo Island")),

        // USA (general - checked after territories)
        (
            ["K", "W", "N", "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AH", "AI", "AJ", "AK", "AL"],
            DXCCEntity(number: 291, name: "United States")
        ),

        // Canada
        (["VE", "VA", "VY", "VO", "CY", "CZ"], DXCCEntity(number: 1, name: "Canada")),

        // Mexico
        (
            ["XE", "XA", "XB", "XC", "XD", "XF", "4A", "4B", "4C", "6D", "6E", "6F", "6G", "6H", "6I", "6J"],
            DXCCEntity(number: 50, name: "Mexico")
        ),

        // Europe
        (["G", "M", "2E", "2M"], DXCCEntity(number: 223, name: "England")),
        (["GW", "MW", "2W"], DXCCEntity(number: 294, name: "Wales")),
        (["GM", "MM", "2M"], DXCCEntity(number: 279, name: "Scotland")),
        (["GI", "MI", "2I"], DXCCEntity(number: 265, name: "Northern Ireland")),
        (["GD", "MD", "2D"], DXCCEntity(number: 114, name: "Isle of Man")),
        (["GJ", "MJ", "2J"], DXCCEntity(number: 122, name: "Jersey")),
        (["GU", "MU", "2U"], DXCCEntity(number: 106, name: "Guernsey")),
        (["F"], DXCCEntity(number: 227, name: "France")),
        (
            ["DL", "DA", "DB", "DC", "DD", "DF", "DG", "DH", "DI", "DJ", "DK", "DM", "DO", "DP", "DQ", "DR"],
            DXCCEntity(number: 230, name: "Germany")
        ),
        (["I", "IK", "IZ", "IU", "IW"], DXCCEntity(number: 248, name: "Italy")),
        (["EA", "EB", "EC", "ED", "EE", "EF", "EG", "EH"], DXCCEntity(number: 281, name: "Spain")),
        (["EA6", "EB6", "EC6", "ED6", "EE6", "EF6"], DXCCEntity(number: 21, name: "Balearic Islands")),
        (["EA8", "EB8", "EC8", "ED8", "EE8", "EF8"], DXCCEntity(number: 29, name: "Canary Islands")),
        (["EA9", "EB9", "EC9", "ED9", "EE9", "EF9"], DXCCEntity(number: 32, name: "Ceuta & Melilla")),
        (["PA", "PB", "PC", "PD", "PE", "PF", "PG", "PH", "PI"], DXCCEntity(number: 263, name: "Netherlands")),
        (["ON", "OO", "OP", "OQ", "OR", "OS", "OT"], DXCCEntity(number: 209, name: "Belgium")),
        (["OE"], DXCCEntity(number: 206, name: "Austria")),
        (["HB9", "HB"], DXCCEntity(number: 287, name: "Switzerland")),
        (["HB0"], DXCCEntity(number: 251, name: "Liechtenstein")),
        (
            ["SM", "SA", "SB", "SC", "SD", "SE", "SF", "SG", "SH", "SI", "SJ", "SK", "SL", "7S", "8S"],
            DXCCEntity(number: 284, name: "Sweden")
        ),
        (
            ["LA", "LB", "LC", "LD", "LE", "LF", "LG", "LH", "LI", "LJ", "LK", "LL", "LM", "LN"],
            DXCCEntity(number: 266, name: "Norway")
        ),
        (["OZ", "OU", "OV", "OW", "XP", "5P", "5Q"], DXCCEntity(number: 221, name: "Denmark")),
        (["OH", "OG", "OI", "OJ"], DXCCEntity(number: 224, name: "Finland")),
        (["SP", "SN", "SO", "SQ", "SR", "3Z"], DXCCEntity(number: 269, name: "Poland")),
        (["OK", "OL"], DXCCEntity(number: 503, name: "Czech Republic")),
        (["OM"], DXCCEntity(number: 504, name: "Slovakia")),
        (["HA", "HG"], DXCCEntity(number: 239, name: "Hungary")),
        (["YO", "YP", "YQ", "YR"], DXCCEntity(number: 275, name: "Romania")),
        (["LZ"], DXCCEntity(number: 212, name: "Bulgaria")),
        (["SV", "SW", "SX", "SY", "SZ", "J4"], DXCCEntity(number: 236, name: "Greece")),
        (["YT", "YU", "4N", "4O"], DXCCEntity(number: 296, name: "Serbia")),
        (["9A"], DXCCEntity(number: 497, name: "Croatia")),
        (["S5"], DXCCEntity(number: 499, name: "Slovenia")),
        (["9H"], DXCCEntity(number: 257, name: "Malta")),
        (["CT"], DXCCEntity(number: 272, name: "Portugal")),
        (["CU"], DXCCEntity(number: 149, name: "Azores")),
        (["CT3"], DXCCEntity(number: 256, name: "Madeira Islands")),
        (["EI", "EJ"], DXCCEntity(number: 245, name: "Ireland")),
        (["OX", "XP"], DXCCEntity(number: 237, name: "Greenland")),
        (["TF"], DXCCEntity(number: 242, name: "Iceland")),
        (["LX"], DXCCEntity(number: 254, name: "Luxembourg")),
        (["3A"], DXCCEntity(number: 260, name: "Monaco")),
        (["T7"], DXCCEntity(number: 278, name: "San Marino")),

        // Russia & Former USSR
        (
            ["UA", "RA", "R", "UA1", "UA3", "UA4", "UA6", "RK", "RN", "RU", "RV", "RW", "RX", "RZ"],
            DXCCEntity(number: 15, name: "European Russia")
        ),
        (["UA9", "UA0", "RA9", "RA0", "R9", "R0", "RK9", "RK0"], DXCCEntity(number: 16, name: "Asiatic Russia")),
        (["UN", "UL", "UM", "UP", "UQ"], DXCCEntity(number: 130, name: "Kazakhstan")),
        (["UK"], DXCCEntity(number: 292, name: "Uzbekistan")),
        (["EX"], DXCCEntity(number: 135, name: "Kyrgyzstan")),
        (["EY"], DXCCEntity(number: 262, name: "Tajikistan")),
        (["EZ"], DXCCEntity(number: 280, name: "Turkmenistan")),
        (["4J", "4K"], DXCCEntity(number: 18, name: "Azerbaijan")),
        (["4L"], DXCCEntity(number: 75, name: "Georgia")),
        (["EK"], DXCCEntity(number: 14, name: "Armenia")),
        (
            ["UR", "US", "UT", "UU", "UV", "UW", "UX", "UY", "UZ", "EM", "EN", "EO"],
            DXCCEntity(number: 288, name: "Ukraine")
        ),
        (["EU", "EV", "EW"], DXCCEntity(number: 27, name: "Belarus")),
        (["LY"], DXCCEntity(number: 146, name: "Lithuania")),
        (["YL"], DXCCEntity(number: 145, name: "Latvia")),
        (["ES"], DXCCEntity(number: 52, name: "Estonia")),
        (["ER"], DXCCEntity(number: 179, name: "Moldova")),

        // Asia
        (
            ["JA", "JD", "JE", "JF", "JG", "JH", "JI", "JJ", "JK", "JL", "JM", "JN", "JO", "JP", "JQ", "JR", "JS", "7J",
             "7K", "7L", "7M", "7N", "8J", "8K", "8L", "8M", "8N"],
            DXCCEntity(number: 339, name: "Japan")
        ),
        (["HL", "DS", "D7", "D8", "D9", "6K", "6L", "6M", "6N"], DXCCEntity(number: 137, name: "South Korea")),
        (["BV", "BW", "BX", "BM", "BN", "BO", "BP", "BQ"], DXCCEntity(number: 386, name: "Taiwan")),
        (
            ["BY", "BA", "BD", "BG", "BH", "BI", "BJ", "BL", "BT", "BZ", "3H", "3I", "3J", "3K", "3L", "3M", "3N", "3O",
             "3P", "3Q", "3R", "3S", "3T", "3U", "XS"],
            DXCCEntity(number: 318, name: "China")
        ),
        (
            ["VU", "AT", "AU", "AV", "AW", "AX", "VT", "VV", "VW", "8T", "8U", "8V", "8W", "8X", "8Y"],
            DXCCEntity(number: 324, name: "India")
        ),
        (["HS", "E2"], DXCCEntity(number: 387, name: "Thailand")),
        (["9M2", "9M4", "9W2", "9W4"], DXCCEntity(number: 299, name: "West Malaysia")),
        (["9M6", "9M8", "9W6", "9W8"], DXCCEntity(number: 46, name: "East Malaysia")),
        (["9V", "S6"], DXCCEntity(number: 381, name: "Singapore")),
        (
            ["YB", "YC", "YD", "YE", "YF", "YG", "YH", "7A", "7B", "7C", "7D", "7E", "7F", "7G", "7H", "7I", "8A", "8B",
             "8C", "8D", "8E", "8F", "8G", "8H", "8I"],
            DXCCEntity(number: 327, name: "Indonesia")
        ),
        (
            ["DU", "DV", "DW", "DX", "DY", "DZ", "4D", "4E", "4F", "4G", "4H", "4I"],
            DXCCEntity(number: 375, name: "Philippines")
        ),
        (["XV", "XU", "3W"], DXCCEntity(number: 293, name: "Vietnam")),
        (["XW"], DXCCEntity(number: 143, name: "Laos")),
        (["XZ", "XY"], DXCCEntity(number: 309, name: "Myanmar")),
        (["EP", "EQ", "9U"], DXCCEntity(number: 330, name: "Iran")),
        (["YI"], DXCCEntity(number: 333, name: "Iraq")),
        (["HZ", "7Z", "8Z"], DXCCEntity(number: 378, name: "Saudi Arabia")),
        (["A4"], DXCCEntity(number: 370, name: "Oman")),
        (["A6"], DXCCEntity(number: 391, name: "United Arab Emirates")),
        (["A7"], DXCCEntity(number: 376, name: "Qatar")),
        (["A9"], DXCCEntity(number: 304, name: "Bahrain")),
        (["9K"], DXCCEntity(number: 348, name: "Kuwait")),
        (["OD"], DXCCEntity(number: 354, name: "Lebanon")),
        (["4X", "4Z"], DXCCEntity(number: 336, name: "Israel")),
        (["JY"], DXCCEntity(number: 342, name: "Jordan")),
        (["TA", "TB", "TC", "YM"], DXCCEntity(number: 390, name: "Turkey")),
        (["AP", "AS", "6P", "6Q", "6R", "6S"], DXCCEntity(number: 372, name: "Pakistan")),
        (["S2", "S3"], DXCCEntity(number: 305, name: "Bangladesh")),
        (["4S"], DXCCEntity(number: 315, name: "Sri Lanka")),
        (["8Q"], DXCCEntity(number: 159, name: "Maldives")),

        // Oceania
        (["VK", "AX"], DXCCEntity(number: 150, name: "Australia")),
        (["ZL", "ZM"], DXCCEntity(number: 170, name: "New Zealand")),
        (["VK9N"], DXCCEntity(number: 189, name: "Norfolk Island")),
        (["VK9L"], DXCCEntity(number: 147, name: "Lord Howe Island")),
        (["VK9C"], DXCCEntity(number: 38, name: "Cocos (Keeling) Islands")),
        (["VK9X"], DXCCEntity(number: 35, name: "Christmas Island")),
        (["VK0H"], DXCCEntity(number: 111, name: "Heard Island")),
        (["VK0M"], DXCCEntity(number: 153, name: "Macquarie Island")),
        (["P2"], DXCCEntity(number: 163, name: "Papua New Guinea")),
        (["YJ"], DXCCEntity(number: 158, name: "Vanuatu")),
        (["3D2", "3D"], DXCCEntity(number: 176, name: "Fiji")),
        (["A3"], DXCCEntity(number: 160, name: "Tonga")),
        (["5W", "ZM7"], DXCCEntity(number: 190, name: "Samoa")),
        (["E5"], DXCCEntity(number: 191, name: "Cook Islands")),
        (["ZK3"], DXCCEntity(number: 283, name: "Tokelau Islands")),
        (["T3"], DXCCEntity(number: 301, name: "Kiribati")),
        (["T2"], DXCCEntity(number: 282, name: "Tuvalu")),
        (["V7"], DXCCEntity(number: 168, name: "Marshall Islands")),
        (["V6"], DXCCEntity(number: 173, name: "Micronesia")),
        (["T8"], DXCCEntity(number: 22, name: "Palau")),
        (["KC6"], DXCCEntity(number: 22, name: "Palau")),

        // Africa
        (["ZS", "ZR", "ZT", "ZU"], DXCCEntity(number: 462, name: "South Africa")),
        (["SU"], DXCCEntity(number: 478, name: "Egypt")),
        (["CN", "5C", "5D", "5E", "5F", "5G"], DXCCEntity(number: 446, name: "Morocco")),
        (["7X"], DXCCEntity(number: 400, name: "Algeria")),
        (["3V", "TS"], DXCCEntity(number: 474, name: "Tunisia")),
        (["5A"], DXCCEntity(number: 436, name: "Libya")),
        (["5T"], DXCCEntity(number: 444, name: "Mauritania")),
        (["5U"], DXCCEntity(number: 450, name: "Niger")),
        (["5V"], DXCCEntity(number: 483, name: "Togo")),
        (["TU"], DXCCEntity(number: 428, name: "Côte d'Ivoire")),
        (["EL"], DXCCEntity(number: 430, name: "Liberia")),
        (["9G"], DXCCEntity(number: 424, name: "Ghana")),
        (["5N"], DXCCEntity(number: 450, name: "Nigeria")),
        (["5Z"], DXCCEntity(number: 430, name: "Kenya")),
        (["5H"], DXCCEntity(number: 470, name: "Tanzania")),
        (["9J"], DXCCEntity(number: 482, name: "Zambia")),
        (["A2"], DXCCEntity(number: 402, name: "Botswana")),
        (["V5"], DXCCEntity(number: 464, name: "Namibia")),
        (["7Q"], DXCCEntity(number: 440, name: "Malawi")),
        (["Z2"], DXCCEntity(number: 452, name: "Zimbabwe")),
        (["D2"], DXCCEntity(number: 401, name: "Angola")),
        (["9X"], DXCCEntity(number: 454, name: "Rwanda")),
        (["9U"], DXCCEntity(number: 404, name: "Burundi")),
        (["TR"], DXCCEntity(number: 420, name: "Gabon")),
        (["TN"], DXCCEntity(number: 412, name: "Republic of Congo")),
        (["TT"], DXCCEntity(number: 408, name: "Chad")),
        (["TJ"], DXCCEntity(number: 406, name: "Cameroon")),
        (["TL"], DXCCEntity(number: 407, name: "Central African Republic")),
        (["ST"], DXCCEntity(number: 466, name: "Sudan")),
        (["ET"], DXCCEntity(number: 488, name: "Ethiopia")),
        (["E3"], DXCCEntity(number: 51, name: "Eritrea")),
        (["6O"], DXCCEntity(number: 232, name: "Somalia")),
        (["6W"], DXCCEntity(number: 456, name: "Senegal")),
        (["C5"], DXCCEntity(number: 422, name: "Gambia")),
        (["9L"], DXCCEntity(number: 458, name: "Sierra Leone")),
        (["D4"], DXCCEntity(number: 409, name: "Cape Verde")),
        (["J5"], DXCCEntity(number: 426, name: "Guinea-Bissau")),
        (["3X"], DXCCEntity(number: 107, name: "Guinea")),
        (["S9"], DXCCEntity(number: 219, name: "São Tomé and Príncipe")),
        (["3C"], DXCCEntity(number: 49, name: "Equatorial Guinea")),
        (["Z8"], DXCCEntity(number: 521, name: "South Sudan")),

        // South America
        (
            ["PY", "PP", "PQ", "PR", "PS", "PT", "PU", "PV", "PW", "PX", "ZV", "ZW", "ZX", "ZY", "ZZ"],
            DXCCEntity(number: 108, name: "Brazil")
        ),
        (
            ["LU", "AY", "AZ", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "LO", "LP", "LQ", "LR", "LS", "LT", "LV",
             "LW"],
            DXCCEntity(number: 100, name: "Argentina")
        ),
        (["CE", "CA", "CB", "CC", "CD", "XQ", "XR", "3G"], DXCCEntity(number: 112, name: "Chile")),
        (["HK", "5J", "5K"], DXCCEntity(number: 116, name: "Colombia")),
        (["YV", "4M"], DXCCEntity(number: 148, name: "Venezuela")),
        (["HC", "HD"], DXCCEntity(number: 120, name: "Ecuador")),
        (["OA", "OB", "OC", "4T"], DXCCEntity(number: 136, name: "Peru")),
        (["CP"], DXCCEntity(number: 104, name: "Bolivia")),
        (["ZP"], DXCCEntity(number: 132, name: "Paraguay")),
        (["CX"], DXCCEntity(number: 144, name: "Uruguay")),
        (["9Y", "9Z"], DXCCEntity(number: 90, name: "Trinidad & Tobago")),
        (["PJ2", "PJ4", "PJ9"], DXCCEntity(number: 517, name: "Curaçao")),
        (["PJ5", "PJ6", "PJ7", "PJ8"], DXCCEntity(number: 519, name: "Sint Maarten")),
        (["P4"], DXCCEntity(number: 91, name: "Aruba")),
        (["8R"], DXCCEntity(number: 129, name: "Guyana")),
        (["PZ"], DXCCEntity(number: 140, name: "Suriname")),
        (["FY"], DXCCEntity(number: 63, name: "French Guiana")),

        // Central America & Caribbean
        (["HR"], DXCCEntity(number: 80, name: "Honduras")),
        (["YS", "HU"], DXCCEntity(number: 74, name: "El Salvador")),
        (["TG", "TD"], DXCCEntity(number: 76, name: "Guatemala")),
        (["TI", "TE"], DXCCEntity(number: 308, name: "Costa Rica")),
        (["HP", "HO", "H3", "H8", "H9"], DXCCEntity(number: 88, name: "Panama")),
        (["YN", "H7", "HT"], DXCCEntity(number: 86, name: "Nicaragua")),
        (["V3"], DXCCEntity(number: 66, name: "Belize")),
        (["HI"], DXCCEntity(number: 72, name: "Dominican Republic")),
        (["HH"], DXCCEntity(number: 78, name: "Haiti")),
        (["CO", "CM", "CL", "T4"], DXCCEntity(number: 70, name: "Cuba")),
        (["6Y"], DXCCEntity(number: 82, name: "Jamaica")),
        (["VP2E", "V2"], DXCCEntity(number: 94, name: "Antigua & Barbuda")),
        (["VP2M"], DXCCEntity(number: 96, name: "Montserrat")),
        (["VP2V", "VP5"], DXCCEntity(number: 65, name: "British Virgin Islands")),
        (["8P"], DXCCEntity(number: 62, name: "Barbados")),
        (["J3"], DXCCEntity(number: 77, name: "Grenada")),
        (["J6"], DXCCEntity(number: 97, name: "Saint Lucia")),
        (["J7"], DXCCEntity(number: 95, name: "Dominica")),
        (["J8"], DXCCEntity(number: 98, name: "St. Vincent")),
        (["V4"], DXCCEntity(number: 249, name: "Saint Kitts & Nevis")),
        (["PJ7"], DXCCEntity(number: 519, name: "Sint Maarten")),
        (["FG", "TO"], DXCCEntity(number: 79, name: "Guadeloupe")),
        (["FM", "TO"], DXCCEntity(number: 84, name: "Martinique")),
        (["VP9"], DXCCEntity(number: 64, name: "Bermuda")),
        (["ZF"], DXCCEntity(number: 69, name: "Cayman Islands")),
        (["C6"], DXCCEntity(number: 60, name: "Bahamas")),
        (["VQ9"], DXCCEntity(number: 33, name: "Chagos Islands")),
    ]

    /// Common callsign prefix to country name mappings for entityDescription
    static let entityDescriptions: [String: String] = [
        // USA
        "K": "United States", "W": "United States", "N": "United States", "A": "United States",
        // Europe
        "G": "England", "M": "England",
        "F": "France",
        "DL": "Germany", "DA": "Germany", "DB": "Germany", "DC": "Germany", "DD": "Germany", "DF": "Germany",
        "DG": "Germany", "DH": "Germany", "DI": "Germany", "DJ": "Germany", "DK": "Germany", "DM": "Germany",
        "DO": "Germany", "DP": "Germany", "DQ": "Germany", "DR": "Germany",
        "I": "Italy",
        "EA": "Spain", "EB": "Spain", "EC": "Spain", "ED": "Spain", "EE": "Spain", "EF": "Spain", "EG": "Spain",
        "EH": "Spain",
        "PA": "Netherlands", "PB": "Netherlands", "PC": "Netherlands", "PD": "Netherlands", "PE": "Netherlands",
        "PF": "Netherlands", "PG": "Netherlands", "PH": "Netherlands", "PI": "Netherlands",
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
        "GW": "Wales", "GM": "Scotland", "GI": "Northern Ireland", "GD": "Isle of Man", "GJ": "Jersey",
        "GU": "Guernsey",
        // Americas
        "VE": "Canada", "VA": "Canada", "VY": "Canada", "VO": "Canada",
        "XE": "Mexico", "XA": "Mexico", "XB": "Mexico", "XC": "Mexico", "XD": "Mexico", "XF": "Mexico",
        "LU": "Argentina",
        "PY": "Brazil", "PP": "Brazil", "PQ": "Brazil", "PR": "Brazil", "PS": "Brazil", "PT": "Brazil",
        "PU": "Brazil",
        "PV": "Brazil", "PW": "Brazil", "PX": "Brazil",
        "CE": "Chile",
        "HK": "Colombia",
        "HC": "Ecuador",
        "OA": "Peru",
        "YV": "Venezuela",
        // Asia/Pacific
        "JA": "Japan", "JD": "Japan", "JE": "Japan", "JF": "Japan", "JG": "Japan", "JH": "Japan", "JI": "Japan",
        "JJ": "Japan", "JK": "Japan", "JL": "Japan", "JM": "Japan", "JN": "Japan", "JO": "Japan", "JP": "Japan",
        "JQ": "Japan", "JR": "Japan", "JS": "Japan",
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
}
