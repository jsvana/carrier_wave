import Foundation

// MARK: - DescriptionLookup DXCC Data

// swiftlint:disable file_length

extension DescriptionLookup {
    /// Look up DXCC entity by entity number
    /// Returns entity with name, or nil if not found
    nonisolated static func dxccEntity(forNumber number: Int) -> DXCCEntity? {
        numberLookup[number]
    }

    /// Pre-built lookup table by entity number for O(1) access
    nonisolated private static let numberLookup: [Int: DXCCEntity] = {
        var result: [Int: DXCCEntity] = [:]
        for (_, entity) in dxccEntities {
            result[entity.number] = entity
        }
        return result
    }()

    // MARK: - DXCC Entity Database

    /// Official DXCC entities with their numbers
    /// Source: ARRL DXCC List - https://www.arrl.org/files/file/DXCC/DXCC_Current.pdf
    /// Prefixes from ITU allocations and cty.dat
    /// Note: Prefixes are checked longest-first to handle special cases like KH6 before K
    nonisolated static let dxccEntities: [(prefixes: [String], entity: DXCCEntity)] = [
        // ==================== US & Territories ====================
        // US Territories (must check before general US prefixes)
        (["KG4"], DXCCEntity(number: 105, name: "Guantanamo Bay")),
        (["KH0", "AH0", "NH0", "WH0"], DXCCEntity(number: 166, name: "Mariana Is.")),
        (["KH1", "AH1", "NH1", "WH1"], DXCCEntity(number: 20, name: "Baker & Howland Is.")),
        (["KH2", "AH2", "NH2", "WH2"], DXCCEntity(number: 103, name: "Guam")),
        (["KH3", "AH3", "NH3", "WH3"], DXCCEntity(number: 123, name: "Johnston I.")),
        (["KH4", "AH4", "NH4", "WH4"], DXCCEntity(number: 174, name: "Midway I.")),
        (["KH5K"], DXCCEntity(number: 138, name: "Kure I.")),
        (["KH5", "AH5", "NH5", "WH5"], DXCCEntity(number: 197, name: "Palmyra & Jarvis Is.")),
        (
            ["KH6", "KH7", "AH6", "AH7", "NH6", "NH7", "WH6", "WH7"],
            DXCCEntity(number: 110, name: "Hawaii")
        ),
        (["KH8S", "AH8S", "NH8S", "WH8S"], DXCCEntity(number: 515, name: "Swains I.")),
        (["KH8", "AH8", "NH8", "WH8"], DXCCEntity(number: 9, name: "American Samoa")),
        (["KH9", "AH9", "NH9", "WH9"], DXCCEntity(number: 297, name: "Wake I.")),
        (
            ["KL7", "KL", "AL7", "AL", "NL7", "NL", "WL7", "WL"],
            DXCCEntity(number: 6, name: "Alaska")
        ),
        (["KP1", "NP1", "WP1"], DXCCEntity(number: 182, name: "Navassa I.")),
        (["KP2", "NP2", "WP2"], DXCCEntity(number: 285, name: "Virgin Is.")),
        (["KP3", "KP4", "NP3", "NP4", "WP3", "WP4"], DXCCEntity(number: 202, name: "Puerto Rico")),
        (["KP5", "NP5", "WP5"], DXCCEntity(number: 43, name: "Desecheo I.")),

        // USA (general - checked after territories)
        (
            ["K", "W", "N", "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AI", "AJ", "AK"],
            DXCCEntity(number: 291, name: "United States of America")
        ),

        // ==================== Canada ====================
        (["VE", "VA", "VO", "VY", "CY", "CZ"], DXCCEntity(number: 1, name: "Canada")),

        // ==================== Mexico ====================
        (
            [
                "XE", "XA", "XB", "XC", "XD", "XF", "4A", "4B", "4C", "6D", "6E", "6F", "6G", "6H",
                "6I", "6J",
            ],
            DXCCEntity(number: 50, name: "Mexico")
        ),
        (["XF4"], DXCCEntity(number: 204, name: "Revillagigedo")),

        // ==================== Europe ====================
        // UK and Crown Dependencies
        (["GD", "GT", "MD", "2D"], DXCCEntity(number: 114, name: "Isle of Man")),
        (["GI", "GN", "MI", "2I"], DXCCEntity(number: 265, name: "Northern Ireland")),
        (["GJ", "GH", "MJ", "2J"], DXCCEntity(number: 122, name: "Jersey")),
        (["GM", "GS", "MM", "2M"], DXCCEntity(number: 279, name: "Scotland")),
        (["GU", "GP", "MU", "2U"], DXCCEntity(number: 106, name: "Guernsey")),
        (["GW", "GC", "MW", "2W"], DXCCEntity(number: 294, name: "Wales")),
        (
            ["G", "M", "2E"],
            DXCCEntity(number: 223, name: "United Kingdom of Great Britain & Northern Ireland")
        ),

        // Western Europe
        (["F"], DXCCEntity(number: 227, name: "France")),
        (
            [
                "DA", "DB", "DC", "DD", "DF", "DG", "DH", "DI", "DJ", "DK", "DL", "DM", "DN", "DO",
                "DP", "DQ", "DR",
            ],
            DXCCEntity(number: 230, name: "Germany")
        ),
        (
            ["PA", "PB", "PC", "PD", "PE", "PF", "PG", "PH", "PI"],
            DXCCEntity(number: 263, name: "Netherlands")
        ),
        (["ON", "OO", "OP", "OQ", "OR", "OS", "OT"], DXCCEntity(number: 209, name: "Belgium")),
        (["LX"], DXCCEntity(number: 254, name: "Luxembourg")),
        (["HB0"], DXCCEntity(number: 251, name: "Liechtenstein")),
        (["HB", "HE"], DXCCEntity(number: 287, name: "Switzerland")),
        (["OE"], DXCCEntity(number: 206, name: "Austria")),

        // Scandinavia
        (["OZ", "OU", "OV", "OW", "5P", "5Q"], DXCCEntity(number: 221, name: "Denmark")),
        (["OX", "XP"], DXCCEntity(number: 237, name: "Greenland")),
        (["OY"], DXCCEntity(number: 222, name: "Faroe Is.")),
        (["JW", "JX"], DXCCEntity(number: 259, name: "Svalbard")),
        (
            ["LA", "LB", "LC", "LD", "LE", "LF", "LG", "LH", "LI", "LJ", "LK", "LL", "LM", "LN"],
            DXCCEntity(number: 266, name: "Norway")
        ),
        (["OJ0"], DXCCEntity(number: 167, name: "Market Reef")),
        (["OH0"], DXCCEntity(number: 5, name: "Aland Is.")),
        (["OH", "OG", "OI", "OJ"], DXCCEntity(number: 224, name: "Finland")),
        (
            [
                "SA", "SB", "SC", "SD", "SE", "SF", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "7S",
                "8S",
            ], DXCCEntity(number: 284, name: "Sweden")
        ),
        (["TF"], DXCCEntity(number: 242, name: "Iceland")),

        // Iberian Peninsula
        (
            ["EA6", "EB6", "EC6", "ED6", "EE6", "EF6", "EG6", "EH6"],
            DXCCEntity(number: 21, name: "Balearic Is.")
        ),
        (
            ["EA8", "EB8", "EC8", "ED8", "EE8", "EF8", "EG8", "EH8"],
            DXCCEntity(number: 29, name: "Canary Is.")
        ),
        (
            ["EA9", "EB9", "EC9", "ED9", "EE9", "EF9", "EG9", "EH9"],
            DXCCEntity(number: 32, name: "Ceuta & Melilla")
        ),
        (["EA", "EB", "EC", "ED", "EE", "EF", "EG", "EH"], DXCCEntity(number: 281, name: "Spain")),
        (["CT3"], DXCCEntity(number: 256, name: "Madeira Is.")),
        (["CU"], DXCCEntity(number: 149, name: "Azores")),
        (["CT", "CS"], DXCCEntity(number: 272, name: "Portugal")),
        (["C3"], DXCCEntity(number: 203, name: "Andorra")),
        (["ZB", "ZG"], DXCCEntity(number: 233, name: "Gibraltar")),

        // Italy and neighbors
        (["IS0", "IM0"], DXCCEntity(number: 225, name: "Sardinia")),
        (["I", "IK", "IN", "IT", "IU", "IW", "IZ"], DXCCEntity(number: 248, name: "Italy")),
        (["T7"], DXCCEntity(number: 278, name: "San Marino")),
        (["HV"], DXCCEntity(number: 295, name: "Vatican")),
        (["3A"], DXCCEntity(number: 260, name: "Monaco")),
        (["9H"], DXCCEntity(number: 257, name: "Malta")),

        // Greece and Eastern Mediterranean
        (["SV5", "J45"], DXCCEntity(number: 45, name: "Dodecanese")),
        (["SV9"], DXCCEntity(number: 40, name: "Crete")),
        (["SY"], DXCCEntity(number: 180, name: "Mount Athos")),
        (["SV", "SW", "SX", "SZ", "J4"], DXCCEntity(number: 236, name: "Greece")),
        (["5B", "C4", "H2", "P3"], DXCCEntity(number: 215, name: "Cyprus")),
        (["ZC4"], DXCCEntity(number: 283, name: "UK Sov. Base Areas on Cyprus")),

        // Central Europe
        (["SP", "SN", "SO", "SQ", "SR", "3Z", "HF"], DXCCEntity(number: 269, name: "Poland")),
        (["OK", "OL"], DXCCEntity(number: 503, name: "Czech Republic")),
        (["OM"], DXCCEntity(number: 504, name: "Slovak Republic")),
        (["HA", "HG"], DXCCEntity(number: 239, name: "Hungary")),
        (["S5"], DXCCEntity(number: 499, name: "Slovenia")),
        (["9A"], DXCCEntity(number: 497, name: "Croatia")),
        (["E7"], DXCCEntity(number: 501, name: "Bosnia-Herzegovina")),
        (["YU", "YT", "4N", "4O"], DXCCEntity(number: 296, name: "Serbia")),
        (["4O"], DXCCEntity(number: 514, name: "Montenegro")),
        (["Z3"], DXCCEntity(number: 502, name: "North Macedonia")),
        (["Z6"], DXCCEntity(number: 522, name: "Republic of Kosovo")),
        (["ZA"], DXCCEntity(number: 7, name: "Albania")),

        // Romania and Bulgaria
        (["YO", "YP", "YQ", "YR"], DXCCEntity(number: 275, name: "Romania")),
        (["LZ"], DXCCEntity(number: 212, name: "Bulgaria")),

        // Ireland
        (["EI", "EJ"], DXCCEntity(number: 245, name: "Ireland")),

        // Baltic States
        (["LY"], DXCCEntity(number: 146, name: "Lithuania")),
        (["YL"], DXCCEntity(number: 145, name: "Latvia")),
        (["ES"], DXCCEntity(number: 52, name: "Estonia")),

        // Belarus, Ukraine, Moldova
        (["EU", "EV", "EW"], DXCCEntity(number: 27, name: "Belarus")),
        (
            ["UR", "US", "UT", "UU", "UV", "UW", "UX", "UY", "UZ", "EM", "EN", "EO"],
            DXCCEntity(number: 288, name: "Ukraine")
        ),
        (["ER"], DXCCEntity(number: 179, name: "Moldova")),

        // Russia
        (["UA2"], DXCCEntity(number: 126, name: "Kaliningrad")),
        (
            [
                "UA9", "UA0", "RA9", "RA0", "R0", "R8", "R9", "RC9", "RC0", "RD9", "RD0", "RE9",
                "RE0", "RF9", "RF0", "RG9", "RG0", "RI0", "RJ9", "RJ0", "RK9", "RK0", "RL9", "RL0",
                "RM9", "RM0", "RN9", "RN0", "RO9", "RO0", "RQ9", "RQ0", "RT9", "RT0", "RU9", "RU0",
                "RV9", "RV0", "RW9", "RW0", "RX9", "RX0", "RY9", "RY0", "RZ9", "RZ0", "U0", "U8",
                "U9",
            ], DXCCEntity(number: 15, name: "Asiatic Russia")
        ),
        (
            [
                "UA", "RA", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "RC", "RD", "RE", "RF", "RG",
                "RI", "RJ", "RK", "RL", "RM", "RN", "RO", "RQ", "RT", "RU", "RV", "RW", "RX", "RY",
                "RZ", "U1", "U2", "U3", "U4", "U5", "U6", "U7",
            ], DXCCEntity(number: 54, name: "European Russia")
        ),

        // ==================== Caucasus & Central Asia ====================
        (["4J", "4K"], DXCCEntity(number: 18, name: "Azerbaijan")),
        (["4L"], DXCCEntity(number: 75, name: "Georgia")),
        (["EK"], DXCCEntity(number: 14, name: "Armenia")),
        (["UN", "UL", "UM", "UP", "UQ"], DXCCEntity(number: 130, name: "Kazakhstan")),
        (["UK"], DXCCEntity(number: 292, name: "Uzbekistan")),
        (["EX"], DXCCEntity(number: 135, name: "Kyrgyz Republic")),
        (["EY"], DXCCEntity(number: 262, name: "Tajikistan")),
        (["EZ"], DXCCEntity(number: 280, name: "Turkmenistan")),

        // ==================== Middle East ====================
        (["TA", "TB", "TC", "YM"], DXCCEntity(number: 390, name: "Republic of Turkiye")),
        (["4X", "4Z"], DXCCEntity(number: 336, name: "Israel")),
        (["E4"], DXCCEntity(number: 510, name: "Palestine")),
        (["JY"], DXCCEntity(number: 342, name: "Jordan")),
        (["OD"], DXCCEntity(number: 354, name: "Lebanon")),
        (["YK"], DXCCEntity(number: 384, name: "Syrian Arab Republic")),
        (["YI"], DXCCEntity(number: 333, name: "Iraq")),
        (["EP", "EQ"], DXCCEntity(number: 330, name: "Iran")),
        (["HZ", "7Z", "8Z"], DXCCEntity(number: 378, name: "Saudi Arabia")),
        (["9K"], DXCCEntity(number: 348, name: "Kuwait")),
        (["A9"], DXCCEntity(number: 304, name: "Bahrain")),
        (["A7"], DXCCEntity(number: 376, name: "Qatar")),
        (["A6"], DXCCEntity(number: 391, name: "United Arab Emirates")),
        (["A4"], DXCCEntity(number: 370, name: "Oman")),
        (["7O"], DXCCEntity(number: 492, name: "Yemen")),

        // ==================== South Asia ====================
        (["AP", "AS", "6P", "6Q", "6R", "6S"], DXCCEntity(number: 372, name: "Pakistan")),
        (["YA", "T6"], DXCCEntity(number: 3, name: "Afghanistan")),
        (
            [
                "VU2", "VU3", "VU4", "VU7", "AT", "AU", "AV", "AW", "8T", "8U", "8V", "8W", "8X",
                "8Y",
            ], DXCCEntity(number: 324, name: "India")
        ),
        (["VU4"], DXCCEntity(number: 11, name: "Andaman & Nicobar Is.")),
        (["VU7"], DXCCEntity(number: 142, name: "Lakshadweep Is.")),
        (["4S", "4R"], DXCCEntity(number: 315, name: "Sri Lanka")),
        (["8Q"], DXCCEntity(number: 159, name: "Maldives")),
        (["S2", "S3"], DXCCEntity(number: 305, name: "Bangladesh")),
        (["9N"], DXCCEntity(number: 369, name: "Nepal")),
        (["A5"], DXCCEntity(number: 306, name: "Bhutan")),

        // ==================== East Asia ====================
        (["JD1O"], DXCCEntity(number: 192, name: "Ogasawara")),
        (["JD1M"], DXCCEntity(number: 177, name: "Minami Torishima")),
        (
            [
                "JA", "JD", "JE", "JF", "JG", "JH", "JI", "JJ", "JK", "JL", "JM", "JN", "JO", "JP",
                "JQ", "JR", "JS", "7J", "7K", "7L", "7M", "7N", "8J", "8K", "8L", "8M", "8N",
            ], DXCCEntity(number: 339, name: "Japan")
        ),
        (["HL", "DS", "6K", "6L", "6M", "6N"], DXCCEntity(number: 137, name: "Republic of Korea")),
        (["P5"], DXCCEntity(number: 344, name: "DPR of Korea")),
        (
            ["BV", "BW", "BX", "BM", "BN", "BO", "BP", "BQ"],
            DXCCEntity(number: 386, name: "Taiwan")
        ),
        (["BV9P"], DXCCEntity(number: 505, name: "Pratas I.")),
        (
            [
                "BY", "BA", "BD", "BG", "BH", "BI", "BJ", "BL", "BT", "BZ", "3H", "3I", "3J", "3K",
                "3L", "3M", "3N", "3O", "3P", "3Q", "3R", "3S", "3T", "3U", "XS",
            ], DXCCEntity(number: 318, name: "China")
        ),
        (["BS7"], DXCCEntity(number: 506, name: "Scarborough Reef")),
        (["VR", "VR2"], DXCCEntity(number: 321, name: "Hong Kong")),
        (["XX9"], DXCCEntity(number: 152, name: "Macao")),
        (["JT", "JU", "JV"], DXCCEntity(number: 363, name: "Mongolia")),

        // ==================== Southeast Asia ====================
        (["HS", "E2"], DXCCEntity(number: 387, name: "Thailand")),
        (["XV", "3W"], DXCCEntity(number: 293, name: "Viet Nam")),
        (["XU"], DXCCEntity(number: 312, name: "Cambodia")),
        (["XW"], DXCCEntity(number: 143, name: "Lao People's Dem Repub")),
        (["XZ", "XY"], DXCCEntity(number: 309, name: "Myanmar")),
        (["9M2", "9M4", "9W2", "9W4"], DXCCEntity(number: 299, name: "West Malaysia")),
        (["9M6", "9M8", "9W6", "9W8"], DXCCEntity(number: 46, name: "East Malaysia")),
        (["9V", "S6"], DXCCEntity(number: 381, name: "Singapore")),
        (["V8"], DXCCEntity(number: 345, name: "Brunei Darussalam")),
        (
            ["DU", "DV", "DW", "DX", "DY", "DZ", "4D", "4E", "4F", "4G", "4H", "4I"],
            DXCCEntity(number: 375, name: "Philippines")
        ),
        (
            [
                "YB", "YC", "YD", "YE", "YF", "YG", "YH", "7A", "7B", "7C", "7D", "7E", "7F", "7G",
                "7H", "7I", "8A", "8B", "8C", "8D", "8E", "8F", "8G", "8H", "8I",
            ], DXCCEntity(number: 327, name: "Indonesia")
        ),
        (["4W"], DXCCEntity(number: 511, name: "Timor - Leste")),

        // ==================== Oceania ====================
        // Australia and territories
        (["VK9N"], DXCCEntity(number: 189, name: "Norfolk I.")),
        (["VK9L"], DXCCEntity(number: 147, name: "Lord Howe I.")),
        (["VK9C"], DXCCEntity(number: 38, name: "Cocos (Keeling) Is.")),
        (["VK9X"], DXCCEntity(number: 35, name: "Christmas I.")),
        (["VK9W"], DXCCEntity(number: 303, name: "Willis I.")),
        (["VK9M"], DXCCEntity(number: 171, name: "Mellish Reef")),
        (["VK0H"], DXCCEntity(number: 111, name: "Heard I.")),
        (["VK0M"], DXCCEntity(number: 153, name: "Macquarie I.")),
        (["VK", "AX"], DXCCEntity(number: 150, name: "Australia")),

        // New Zealand and territories
        (["ZL7"], DXCCEntity(number: 34, name: "Chatham Is.")),
        (["ZL8"], DXCCEntity(number: 133, name: "Kermadec Is.")),
        (["ZL9"], DXCCEntity(number: 16, name: "New Zealand Subantarctic Islands")),
        (["ZL", "ZM"], DXCCEntity(number: 170, name: "New Zealand")),

        // Pacific Islands
        (["P2"], DXCCEntity(number: 163, name: "Papua New Guinea")),
        (["H4"], DXCCEntity(number: 185, name: "Solomon Is.")),
        (["H40"], DXCCEntity(number: 507, name: "Temotu Province")),
        (["YJ"], DXCCEntity(number: 158, name: "Vanuatu")),
        (["FK"], DXCCEntity(number: 162, name: "New Caledonia")),
        (["TX"], DXCCEntity(number: 512, name: "Chesterfield Is.")),
        (["3D2R"], DXCCEntity(number: 460, name: "Rotuma I.")),
        (["3D2C"], DXCCEntity(number: 489, name: "Conway Reef")),
        (["3D2", "3D"], DXCCEntity(number: 176, name: "Fiji")),
        (["A3"], DXCCEntity(number: 160, name: "Tonga")),
        (["5W"], DXCCEntity(number: 190, name: "Samoa")),
        (["ZK3"], DXCCEntity(number: 270, name: "Tokelau Is.")),
        (["E51N"], DXCCEntity(number: 191, name: "N. Cook Is.")),
        (["E51S"], DXCCEntity(number: 234, name: "S. Cook Is.")),
        (["E5"], DXCCEntity(number: 191, name: "N. Cook Is.")),
        (["ZK2"], DXCCEntity(number: 188, name: "Niue")),
        (["FO0M"], DXCCEntity(number: 509, name: "Marquesas Is.")),
        (["FO0"], DXCCEntity(number: 175, name: "French Polynesia")),
        (["FO"], DXCCEntity(number: 508, name: "Austral I.")),
        (["T32"], DXCCEntity(number: 48, name: "E. Kiribati")),
        (["T31"], DXCCEntity(number: 31, name: "C. Kiribati")),
        (["T33"], DXCCEntity(number: 490, name: "Banaba I.")),
        (["T30"], DXCCEntity(number: 301, name: "W. Kiribati")),
        (["T2"], DXCCEntity(number: 282, name: "Tuvalu")),
        (["V7"], DXCCEntity(number: 168, name: "Marshall Is.")),
        (["V6"], DXCCEntity(number: 173, name: "Micronesia")),
        (["T8", "KC6"], DXCCEntity(number: 22, name: "Palau")),
        (["KX6"], DXCCEntity(number: 168, name: "Marshall Is.")),
        (["C2"], DXCCEntity(number: 157, name: "Nauru")),
        (["T3"], DXCCEntity(number: 301, name: "W. Kiribati")),
        (["FW"], DXCCEntity(number: 298, name: "Wallis & Futuna Is.")),
        (["VP6D"], DXCCEntity(number: 513, name: "Ducie I.")),
        (["VP6"], DXCCEntity(number: 172, name: "Pitcairn I.")),
        (["CE0X"], DXCCEntity(number: 217, name: "San Felix & San Ambrosio")),
        (["CE0Y"], DXCCEntity(number: 47, name: "Easter I.")),
        (["CE0Z"], DXCCEntity(number: 125, name: "Juan Fernandez Is.")),

        // ==================== Africa ====================
        // North Africa
        (["SU"], DXCCEntity(number: 478, name: "Egypt")),
        (["5A"], DXCCEntity(number: 436, name: "Libya")),
        (["3V", "TS"], DXCCEntity(number: 474, name: "Tunisia")),
        (["7X"], DXCCEntity(number: 400, name: "Algeria")),
        (["CN", "5C", "5D", "5E", "5F", "5G"], DXCCEntity(number: 446, name: "Morocco")),
        (["S0"], DXCCEntity(number: 302, name: "Western Sahara")),

        // West Africa
        (["5T"], DXCCEntity(number: 444, name: "Mauritania")),
        (["6W"], DXCCEntity(number: 456, name: "Senegal")),
        (["C5"], DXCCEntity(number: 422, name: "Gambia")),
        (["J5"], DXCCEntity(number: 109, name: "Guinea-Bissau")),
        (["3X"], DXCCEntity(number: 107, name: "Guinea")),
        (["9L"], DXCCEntity(number: 458, name: "Sierra Leone")),
        (["EL"], DXCCEntity(number: 434, name: "Liberia")),
        (["TU"], DXCCEntity(number: 428, name: "Cote d'Ivoire")),
        (["XT"], DXCCEntity(number: 480, name: "Burkina Faso")),
        (["9G"], DXCCEntity(number: 424, name: "Ghana")),
        (["5V"], DXCCEntity(number: 483, name: "Togo")),
        (["TY"], DXCCEntity(number: 416, name: "Benin")),
        (["5U"], DXCCEntity(number: 187, name: "Niger")),
        (["5N"], DXCCEntity(number: 450, name: "Nigeria")),

        // Central Africa
        (["TT"], DXCCEntity(number: 410, name: "Chad")),
        (["TL"], DXCCEntity(number: 408, name: "Central Africa")),
        (["TJ"], DXCCEntity(number: 406, name: "Cameroon")),
        (["3C"], DXCCEntity(number: 49, name: "Equatorial Guinea")),
        (["3C0"], DXCCEntity(number: 195, name: "Annobon I.")),
        (["TR"], DXCCEntity(number: 420, name: "Gabon")),
        (["S9"], DXCCEntity(number: 219, name: "Sao Tome & Principe")),
        (["TN"], DXCCEntity(number: 412, name: "Congo")),
        (["9Q", "9R", "9S", "9T"], DXCCEntity(number: 414, name: "Dem. Rep. of the Congo")),
        (["D2"], DXCCEntity(number: 401, name: "Angola")),

        // East Africa
        (["ST"], DXCCEntity(number: 466, name: "Sudan")),
        (["Z8"], DXCCEntity(number: 521, name: "South Sudan")),
        (["ET", "E3"], DXCCEntity(number: 53, name: "Ethiopia")),
        (["E3"], DXCCEntity(number: 51, name: "Eritrea")),
        (["J2"], DXCCEntity(number: 382, name: "Djibouti")),
        (["6O", "T5"], DXCCEntity(number: 232, name: "Somalia")),
        (["5Z"], DXCCEntity(number: 430, name: "Kenya")),
        (["5X"], DXCCEntity(number: 286, name: "Uganda")),
        (["5H"], DXCCEntity(number: 470, name: "Tanzania")),
        (["9U"], DXCCEntity(number: 404, name: "Burundi")),
        (["9X"], DXCCEntity(number: 454, name: "Rwanda")),

        // Southern Africa
        (["9J"], DXCCEntity(number: 482, name: "Zambia")),
        (["7Q"], DXCCEntity(number: 440, name: "Malawi")),
        (["C9"], DXCCEntity(number: 181, name: "Mozambique")),
        (["Z2"], DXCCEntity(number: 452, name: "Zimbabwe")),
        (["A2"], DXCCEntity(number: 402, name: "Botswana")),
        (["V5"], DXCCEntity(number: 464, name: "Namibia")),
        (["7P"], DXCCEntity(number: 432, name: "Lesotho")),
        (["3DA"], DXCCEntity(number: 468, name: "Kingdom of Eswatini")),
        (["ZS8"], DXCCEntity(number: 201, name: "Prince Edward & Marion Is.")),
        (["ZS", "ZR", "ZT", "ZU"], DXCCEntity(number: 462, name: "South Africa")),

        // Indian Ocean Africa
        (["5R"], DXCCEntity(number: 438, name: "Madagascar")),
        (["D6"], DXCCEntity(number: 411, name: "Comoros")),
        (["FT5Z", "FT/Z"], DXCCEntity(number: 10, name: "Amsterdam & St. Paul Is.")),
        (["FT5W", "FT/W"], DXCCEntity(number: 41, name: "Crozet I.")),
        (["FT5X", "FT/X"], DXCCEntity(number: 131, name: "Kerguelen Is.")),
        (["FH"], DXCCEntity(number: 169, name: "Mayotte")),
        (["FR", "FT"], DXCCEntity(number: 453, name: "Reunion I.")),
        (["FR/G", "FT/G"], DXCCEntity(number: 99, name: "Glorioso Is.")),
        (["FR/J", "FT/J"], DXCCEntity(number: 124, name: "Juan de Nova & Europa")),
        (["FR/T", "FT/T"], DXCCEntity(number: 276, name: "Tromelin I.")),
        (["3B6", "3B7"], DXCCEntity(number: 4, name: "Agalega & St. Brandon Is.")),
        (["3B8"], DXCCEntity(number: 165, name: "Mauritius")),
        (["3B9"], DXCCEntity(number: 207, name: "Rodrigues I.")),
        (["S7"], DXCCEntity(number: 379, name: "Seychelles")),
        (["D4"], DXCCEntity(number: 409, name: "Cabo Verde")),

        // Atlantic Ocean Africa
        (["ZD7"], DXCCEntity(number: 250, name: "St. Helena")),
        (["ZD8"], DXCCEntity(number: 205, name: "Ascension I.")),
        (["ZD9"], DXCCEntity(number: 274, name: "Tristan da Cunha & Gough I.")),

        // ==================== South America ====================
        (["PP0F", "PY0F"], DXCCEntity(number: 56, name: "Fernando de Noronha")),
        (["PP0S", "PY0S"], DXCCEntity(number: 253, name: "St. Peter & St. Paul Rocks")),
        (["PP0T", "PY0T"], DXCCEntity(number: 273, name: "Trindade & Martim Vaz Is.")),
        (
            [
                "PP", "PQ", "PR", "PS", "PT", "PU", "PV", "PW", "PX", "PY", "ZV", "ZW", "ZX", "ZY",
                "ZZ",
            ], DXCCEntity(number: 108, name: "Brazil")
        ),
        (
            [
                "LU", "AY", "AZ", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "LO", "LP", "LQ",
                "LR", "LS", "LT", "LV", "LW",
            ], DXCCEntity(number: 100, name: "Argentina")
        ),
        (["CE", "CA", "CB", "CC", "CD", "XQ", "XR", "3G"], DXCCEntity(number: 112, name: "Chile")),
        (["HK", "5J", "5K"], DXCCEntity(number: 116, name: "Colombia")),
        (["HK0M"], DXCCEntity(number: 161, name: "Malpelo I.")),
        (["HK0"], DXCCEntity(number: 216, name: "San Andres & Providencia")),
        (["YV0"], DXCCEntity(number: 17, name: "Aves I.")),
        (["YV", "4M"], DXCCEntity(number: 148, name: "Venezuela")),
        (["HC", "HD"], DXCCEntity(number: 120, name: "Ecuador")),
        (["HC8", "HD8"], DXCCEntity(number: 71, name: "Galapagos Is.")),
        (["OA", "OB", "OC", "4T"], DXCCEntity(number: 136, name: "Peru")),
        (["CP"], DXCCEntity(number: 104, name: "Bolivia")),
        (["ZP"], DXCCEntity(number: 132, name: "Paraguay")),
        (["CX"], DXCCEntity(number: 144, name: "Uruguay")),
        (["8R"], DXCCEntity(number: 129, name: "Guyana")),
        (["PZ"], DXCCEntity(number: 140, name: "Suriname")),
        (["FY"], DXCCEntity(number: 63, name: "French Guiana")),

        // ==================== Central America ====================
        (["HR"], DXCCEntity(number: 80, name: "Honduras")),
        (["YS", "HU"], DXCCEntity(number: 74, name: "El Salvador")),
        (["TG"], DXCCEntity(number: 76, name: "Guatemala")),
        (["TI", "TE"], DXCCEntity(number: 308, name: "Costa Rica")),
        (["TI9"], DXCCEntity(number: 37, name: "Cocos I.")),
        (["HP", "HO", "H3", "H8", "H9"], DXCCEntity(number: 88, name: "Panama")),
        (["YN", "H7", "HT"], DXCCEntity(number: 86, name: "Nicaragua")),
        (["V3"], DXCCEntity(number: 66, name: "Belize")),

        // ==================== Caribbean ====================
        (["HI"], DXCCEntity(number: 72, name: "Dominican Republic")),
        (["HH"], DXCCEntity(number: 78, name: "Haiti")),
        (["CO", "CM", "CL", "T4"], DXCCEntity(number: 70, name: "Cuba")),
        (["6Y"], DXCCEntity(number: 82, name: "Jamaica")),
        (["ZF"], DXCCEntity(number: 69, name: "Cayman Is.")),
        (["C6"], DXCCEntity(number: 60, name: "Bahamas")),
        (["VP5"], DXCCEntity(number: 89, name: "Turks & Caicos Is.")),
        (["VP9"], DXCCEntity(number: 64, name: "Bermuda")),
        (["VP2E", "V2"], DXCCEntity(number: 94, name: "Antigua & Barbuda")),
        (["VP2M"], DXCCEntity(number: 96, name: "Montserrat")),
        (["VP2A"], DXCCEntity(number: 12, name: "Anguilla")),
        (["VP2V"], DXCCEntity(number: 65, name: "British Virgin Is.")),
        (["8P"], DXCCEntity(number: 62, name: "Barbados")),
        (["J3"], DXCCEntity(number: 77, name: "Grenada")),
        (["J6"], DXCCEntity(number: 97, name: "St. Lucia")),
        (["J7"], DXCCEntity(number: 95, name: "Dominica")),
        (["J8"], DXCCEntity(number: 98, name: "St. Vincent")),
        (["V4"], DXCCEntity(number: 249, name: "St. Kitts & Nevis")),
        (["9Y", "9Z"], DXCCEntity(number: 90, name: "Trinidad & Tobago")),
        (["PJ2"], DXCCEntity(number: 517, name: "Curacao")),
        (["PJ4"], DXCCEntity(number: 520, name: "Bonaire")),
        (["PJ5", "PJ6"], DXCCEntity(number: 519, name: "Saba & St. Eustatius")),
        (["PJ7"], DXCCEntity(number: 518, name: "Sint Maarten")),
        (["P4"], DXCCEntity(number: 91, name: "Aruba")),
        (["FG"], DXCCEntity(number: 79, name: "Guadeloupe")),
        (["FS"], DXCCEntity(number: 213, name: "Saint Martin")),
        (["FJ"], DXCCEntity(number: 516, name: "Saint Barthelemy")),
        (["FM"], DXCCEntity(number: 84, name: "Martinique")),
        (["FP"], DXCCEntity(number: 277, name: "St. Pierre & Miquelon")),

        // ==================== Atlantic Islands ====================
        (["CY0"], DXCCEntity(number: 211, name: "Sable I.")),
        (["CY9"], DXCCEntity(number: 252, name: "St. Paul I.")),
        (["VP8/F", "VP8F"], DXCCEntity(number: 141, name: "Falkland Is.")),
        (["VP8/G", "VP8G"], DXCCEntity(number: 235, name: "South Georgia I.")),
        (["VP8/O", "VP8O"], DXCCEntity(number: 238, name: "South Orkney Is.")),
        (["VP8/H", "VP8H"], DXCCEntity(number: 240, name: "South Sandwich Is.")),
        (["VP8/S", "VP8S"], DXCCEntity(number: 241, name: "South Shetland Is.")),
        (["CE9", "VP8"], DXCCEntity(number: 13, name: "Antarctica")),
        (["FO0C"], DXCCEntity(number: 36, name: "Clipperton I.")),
        (["VQ9"], DXCCEntity(number: 33, name: "Chagos Is.")),

        // ==================== Special Entities ====================
        (["4U1I"], DXCCEntity(number: 117, name: "ITU HQ")),
        (["4U1U"], DXCCEntity(number: 289, name: "United Nations HQ")),
        (["1A"], DXCCEntity(number: 246, name: "Sov. Mil. Order of Malta")),
        (["BQ9"], DXCCEntity(number: 247, name: "Spratly Is.")),
        (["RI1F"], DXCCEntity(number: 61, name: "Franz Josef Land")),
        (["3Y0B"], DXCCEntity(number: 24, name: "Bouvet")),
        (["3Y0P"], DXCCEntity(number: 199, name: "Peter 1 I.")),
    ]

    // MARK: - Entity Descriptions (for simple prefix -> country name lookup)

    /// Common callsign prefix to country name mappings for entityDescription
    static let entityDescriptions: [String: String] = [
        // USA
        "K": "United States", "W": "United States", "N": "United States", "A": "United States",
        // Europe
        "G": "England", "M": "England",
        "F": "France",
        "DL": "Germany", "DA": "Germany", "DB": "Germany", "DC": "Germany", "DD": "Germany",
        "DF": "Germany", "DG": "Germany", "DH": "Germany", "DI": "Germany", "DJ": "Germany",
        "DK": "Germany", "DM": "Germany", "DO": "Germany", "DP": "Germany", "DQ": "Germany",
        "DR": "Germany",
        "I": "Italy",
        "EA": "Spain", "EB": "Spain", "EC": "Spain", "ED": "Spain", "EE": "Spain",
        "EF": "Spain", "EG": "Spain", "EH": "Spain",
        "PA": "Netherlands", "PB": "Netherlands", "PC": "Netherlands", "PD": "Netherlands",
        "PE": "Netherlands", "PF": "Netherlands", "PG": "Netherlands", "PH": "Netherlands",
        "PI": "Netherlands",
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
        "GW": "Wales", "GM": "Scotland", "GI": "Northern Ireland", "GD": "Isle of Man",
        "GJ": "Jersey", "GU": "Guernsey",
        // Americas
        "VE": "Canada", "VA": "Canada", "VY": "Canada", "VO": "Canada",
        "XE": "Mexico", "XA": "Mexico", "XB": "Mexico", "XC": "Mexico", "XD": "Mexico",
        "XF": "Mexico",
        "LU": "Argentina",
        "PY": "Brazil", "PP": "Brazil", "PQ": "Brazil", "PR": "Brazil", "PS": "Brazil",
        "PT": "Brazil", "PU": "Brazil", "PV": "Brazil", "PW": "Brazil", "PX": "Brazil",
        "CE": "Chile",
        "HK": "Colombia",
        "HC": "Ecuador",
        "OA": "Peru",
        "YV": "Venezuela",
        // Asia/Pacific
        "JA": "Japan", "JD": "Japan", "JE": "Japan", "JF": "Japan", "JG": "Japan",
        "JH": "Japan", "JI": "Japan", "JJ": "Japan", "JK": "Japan", "JL": "Japan",
        "JM": "Japan", "JN": "Japan", "JO": "Japan", "JP": "Japan", "JQ": "Japan",
        "JR": "Japan", "JS": "Japan",
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

// swiftlint:enable file_length
