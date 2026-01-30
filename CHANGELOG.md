# Changelog

All notable changes to Carrier Wave will be documented in this file.

## [1.13.1] - 2026-01-29

### Fixed
- LoFi sync debug logging now appears in in-app sync logs and bug reports (was only going to system console)

## [1.13.0] - 2026-01-29

### Added
- **Under Construction Banner** - Dismissible warning for features still in development
  - Shows on Logger and CW Decoder tabs
  - Can be dismissed per-session or permanently hidden
- **Keyboard Number Row** - Quick frequency entry in Logger
  - Number row (0-9 and decimal) appears above keyboard when entering callsigns
  - Keyboard dismiss button to hide keyboard
- **Enhanced LoFi Sync Debugging** - Comprehensive logging for diagnosing sync issues
  - Logs account cutoff_date from registration response (explains limited data access)
  - Logs operation and QSO count mismatches with expected vs actual totals
  - Logs date ranges of operations and QSOs fetched
  - Logs pagination details (records_left, synced_until, synced_since)
  - Logs per-operation QSO count mismatches with POTA reference and date info
  - Warning when 0 QSOs returned for operations that should have data
  - Bug reports now include LoFi-specific details (linked status, callsign, last sync timestamp)
- **QSO Logger Tab** - Streamlined logging for activations and casual operating
  - Session-based logging with configurable wizard (mode, frequency, activation type)
  - Soft delete pattern - QSOs are hidden, never truly deleted (WAL durability)
  - Command input: type frequency (14.060), MODE, SPOT, RBN, SOLAR, WEATHER in callsign field
  - Callsign lookup integration (Polo notes + QRZ) with info card display
  - RST fields with expandable "More" section for notes, their park, operator
  - Recent QSOs list filtered by current session
- **RBN Integration** - Real-time Reverse Beacon Network spots
  - RBN panel showing your spots with signal strength and timing
  - Mini-map view showing spotter locations
  - Frequency activity monitoring (±2kHz) with QRM assessment
- **Solar & Weather Conditions** - NOAA data integration
  - Solar panel showing K-index, SFI, propagation forecast
  - HF band outlook based on current conditions
  - Weather panel from NOAA with outdoor/antenna/equipment advisories
- **Band Plan Validation** - License class privilege checking
  - Warning banner when operating outside license privileges
  - Technician/General/Extra class support
  - Mode validation (CW vs SSB segments)
- **POTA Self-Spotting** - Post spots directly from the logger
  - Integrates with existing POTA authentication
  - One-command spotting during activations
- **Toast Notifications** - Feedback for logger actions
  - QSO logged, spot posted, command executed confirmations
  - Friend spotted alerts when friends appear on RBN
- **CW Adaptive Frequency Detection** - Automatically detects CW tone frequency within a configurable range
  - Filter bank of Goertzel filters scans 400-900 Hz (default) with 50 Hz spacing
  - Locks onto detected frequency after confirmation, stays locked during gaps between elements
  - Three range presets: Wide (400-900 Hz), Normal (500-800 Hz), Narrow (550-700 Hz)
  - Toggle between adaptive and fixed frequency modes in settings menu
  - Detected frequency displayed in UI with auto-detect indicator
- **CW Chat Transcription** - View decoded CW as a conversation between stations
  - Chat/Raw toggle to switch between conversation bubbles and raw transcript
  - Turn detection using frequency changes and prosigns (DE, K, KN, BK)
  - Messages grouped by speaker with callsign attribution
  - Left/right aligned bubbles for other station vs. you
- **Enhanced CW Highlighting** - More intelligent text pattern detection
  - Grid squares highlighted (e.g., EM74)
  - Power levels highlighted (e.g., 100W)
  - Operator names highlighted after NAME/OP keywords
  - Signal reports highlighted with "UR" prefix context
- **Callsign Lookup** - Automatic callsign information from multiple sources
  - Polo notes lists checked first (local, fast, offline)
  - Name and emoji displayed in chat bubbles when available
  - Two-tier lookup architecture ready for QRZ XML API

## [1.12.0] - 2026-01-28

### Added
- **iPad Support** - Full iPad-optimized layouts following Apple HIG
  - Sidebar navigation on iPad (NavigationSplitView) instead of tab bar
  - Activity view uses side-by-side layout (challenges + feed columns)
  - Dashboard stats grid shows all 6 stats in one row on iPad
  - Activity grid dynamically shows 26-52 weeks based on screen width
  - iPhone retains existing TabView navigation (unchanged)

## [1.11.1] - 2026-01-28

### Fixed
- Crash during sync when evaluating challenge progress (SwiftData predicate used computed property instead of stored property)

## [1.11.0] - 2026-01-28

### Added
- **Activity tab** (renamed from Challenges)
  - Activity feed showing friend, club, and personal activities
  - Filter bar to show All, Friends only, or Clubs only
  - Activity detection for notable events (new DXCC, bands, modes, DX contacts, streaks)
  - Automatic activity reporting to server during sync
- **Friends**
  - Friends list showing accepted friends and pending requests
  - Friend search by callsign
  - Send, accept, and reject friend requests
- **Clubs**
  - Clubs list showing memberships (via Polo notes lists)
  - Club detail view with member list
- **Adaptive sync for rate limiting**
  - LoTW: Adaptive date windowing automatically shrinks time windows when hitting rate limits
  - POTA: Adaptive batch processing adjusts batch size on timeouts
  - Resumable downloads with checkpoints survive app restarts
- **Tour updates**
  - Activity tab added to intro tour
  - Expanded social mini-tour explaining friends and clubs
- "Ready to Upload" section in POTA Activations view
  - Pending activations pinned to top, sorted by date descending
  - Park reference shown in each row for easy identification

### Fixed
- POTA tour text changed from "AWS Cognito" to "External Logins (Google, Apple, etc.)" for clarity
- Map confirmed filter now includes QSOs confirmed by either QRZ or LoTW (union)
- Crash after device sleep when evaluating challenge progress
- Sync pagination handling improved

## [1.10.0] - 2026-01-28

### Added
- QSO Map view improvements:
  - States and DXCC counts in stats overlay
  - "Show Individual QSOs" toggle for small dot markers per QSO
  - Always-visible active filters display (dates, band, mode, park, confirmed)
  - Geodesic curve paths to contacted stations (renamed from "Show Arcs")
  - Performance limit (500 QSOs) with toggle to show all
- Streak statistics improvements:
  - POTA section showing valid/attempted activation counts
  - Best streak date ranges now include year
- Intro tour updates:
  - New Statistics step highlighting streaks and activity tracking
  - New Map step highlighting geodesic paths and filters

### Fixed
- Map date picker now defaults to earliest QSO date instead of invalid date
- Metadata modes (SOLAR, WEATHER, NOTE) filtered from map mode picker
- All streaks now use UTC consistently for date calculations
- Tour text alignment in Track Your Progress step
- Swift 6 concurrency warnings

## [1.9.0] - 2026-01-27

### Added
- Callsign Aliases feature for users who have changed callsigns over time
  - Configure current callsign and list of previous callsigns in Settings
  - Auto-detects multiple callsigns in QSO data and suggests adding as aliases
  - QRZ sync now properly matches QSOs logged under any user callsign
  - Current callsign auto-populated from QRZ on first connection

## [1.8.3] - 2026-01-27

### Added
- "Request a Feature" button in Settings linking to Discord

### Fixed
- Deduplication now treats equivalent modes as duplicates (PHONE/SSB/USB/LSB/AM/FM/DV, DATA/FT8/FT4/PSK31/RTTY)
- When merging duplicates, the more specific mode is preserved (e.g., SSB over PHONE)

## [1.8.2] - 2026-01-27

### Added
- Bug report feature with clipboard copy and Discord link in Settings
- Discord server link in Settings

### Fixed
- Configure button on dashboard service cards now navigates to settings instead of spinning indefinitely

## [1.8.0] - 2026-01-27

### Changed
- Redesigned dashboard services section as a compact vertical stacked list
  - Replaced 2x3 grid of large cards (~130pt each) with HIG-compliant list rows (~44pt each)
  - Each service shows status indicator, name, sync count, and optional secondary stats
  - Tapping a service opens a detail sheet with full stats and actions
- Consistent "Not configured" status text across all services

### Fixed
- Consider park reference when merging duplicate QSOs

## [1.7.0] - 2026-01-26

### Added
- POTA parks cache for displaying human-readable park names throughout the app

### Fixed
- Dashboard activation stats now match POTA activations view calculations
- Swift 6 concurrency warnings in POTAParksCache

## [1.6.0] - 2026-01-26

### Fixed
- Handle case where user hasn't finished POTA account setup
- POTA login and activation grouping improvements
- Show QSO rows in POTA uploads view

## [1.5.0] - 2026-01-25

### Added
- Force re-download debug buttons for all services (LoFi, HAMRS, LoTW, QRZ, POTA)
- Methods to force re-download and reprocess QSOs from any service

### Fixed
- POTA uploads reliability improvements
- DXCC entity handling

## [1.2.0] - 2026-01-25

### Added
- QRZ QSL confirmed count on dashboard
- POTA Activations view replacing POTA Uploads segment
  - QSOs grouped by park and date
  - Shows activation status (valid/incomplete)
- POTA maintenance window handling (0000-0400 UTC)
  - Countdown timer on dashboard
  - Uploads automatically skipped during maintenance
  - Developer bypass option in debug mode
- Connected status icons for all services

### Changed
- Reorganized POTA views into POTAActivations directory

### Fixed
- Remove logout/disconnect menus from dashboard service cards
- POTA sync button disabled during maintenance window
- WebView creation dispatched to main actor
- Handle POTA 403 errors same as 401

## [1.1.0] - 2026-01-25

### Added
- POTA maintenance window detection and handling
- LoTW integration for QSL confirmations
- QSLs stat card on dashboard (replacing Modes)

### Changed
- Various UI improvements following Apple HIG

## [1.0.0] - 2026-01-24

### Added
- Initial release
- QSO logging with SwiftData persistence
- Cloud sync to QRZ, POTA, Ham2K LoFi, HAMRS, and LoTW
- iCloud file monitoring for ADIF imports
- Dashboard with activity grid and statistics
- DXCC entity tracking
- Grid square tracking
- Band and mode statistics
