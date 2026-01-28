# Changelog

All notable changes to Carrier Wave will be documented in this file.

## [1.11.0] - 2026-01-28

### Added
- "Ready to Upload" section in POTA Activations view
  - Pending activations pinned to top, sorted by date descending
  - Park reference shown in each row for easy identification
  - Existing "grouped by park" sections remain below

### Fixed
- POTA tour text changed from "AWS Cognito" to "External Logins (Google, Apple, etc.)" for clarity
- Map confirmed filter now includes QSOs confirmed by either QRZ or LoTW (union)
- Crash after device sleep when evaluating challenge progress
  - ChallengesView now uses fresh ModelContext instead of cached reference

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
