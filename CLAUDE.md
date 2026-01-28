# Carrier Wave

> **IMPORTANT:** For general project context, read this file and linked docs.
> Only explore source files when actively implementing, planning, or debugging.

## File Discovery Rules

**FORBIDDEN:**
- Scanning all `.swift` files (e.g., `Glob **/*.swift`, `Grep` across entire repo)
- Using Task/Explore agents to "find all files" or "explore the codebase structure"
- Any broad file discovery that reads more than 5 files at once

**REQUIRED:**
- Use the File Index below to locate files by feature/purpose
- Read specific files by path from the index
- When editing files, update this index if adding/removing/renaming files

## File Index

### Entry Points
| File | Purpose |
|------|---------|
| `CarrierWave/CarrierWaveApp.swift` | App entry point, SwiftData container setup |
| `CarrierWave/ContentView.swift` | Root TabView with AppTab enum for programmatic tab switching |

### Models (`CarrierWave/Models/`)
| File | Purpose |
|------|---------|
| `QSO.swift` | Core contact record (callsign, band, mode, timestamps, grid, park ref) |
| `UploadDestination.swift` | Sync target configuration (enabled flag, last sync timestamp) |
| `POTAJob.swift` | POTA activation job tracking |
| `POTALogEntry.swift` | Individual POTA log entries |
| `POTAUploadAttempt.swift` | POTA upload attempt history and status |
| `ServicePresence.swift` | Service connection status tracking |
| `ActivationMetadata.swift` | Activation-level metadata storage |
| `StatCategoryItem.swift` | Individual stat item for dashboard display |
| `StatCategoryType.swift` | Stat category enum (band, mode, DXCC, etc.) |
| `Types.swift` | Shared type definitions |
| `ChallengeDefinition.swift` | Challenge metadata and rules |
| `ChallengeParticipation.swift` | User's participation in a challenge |
| `ChallengeSource.swift` | Where challenge definitions come from |
| `ChallengeTypes.swift` | Challenge-related enums and types |
| `LeaderboardCache.swift` | Cached leaderboard data |
| `POTAActivation.swift` | POTA activation grouping view model |

### Services (`CarrierWave/Services/`)
| File | Purpose |
|------|---------|
| `QRZClient.swift` | QRZ.com API client (session auth) |
| `QRZClient+ADIF.swift` | QRZ ADIF upload extension |
| `POTAClient.swift` | POTA API client (bearer token auth) |
| `POTAClient+Upload.swift` | POTA multipart ADIF upload |
| `POTAClient+ADIF.swift` | POTA ADIF formatting |
| `POTAClient+GridLookup.swift` | POTA grid square lookup |
| `POTAParksCache.swift` | POTA park reference to name lookup cache |
| `POTAAuthService.swift` | POTA OAuth flow handling (main service) |
| `POTAAuthService+JavaScript.swift` | JavaScript helpers for POTA WebView auth |
| `POTAAuthService+HeadlessAuth.swift` | Headless authentication with stored credentials |
| `LoFiClient.swift` | Ham2K LoFi sync client |
| `LoFiClient+Helpers.swift` | LoFi helper methods |
| `LoFiModels.swift` | LoFi API response models |
| `LoTWClient.swift` | LoTW API client (download-only, username/password auth) |
| `LoTWError.swift` | LoTW-specific errors |
| `HAMRSClient.swift` | HAMRS sync client |
| `HAMRSModels.swift` | HAMRS API models |
| `HAMRSError.swift` | HAMRS-specific errors |
| `SyncService.swift` | Main sync orchestrator |
| `SyncService+Upload.swift` | Upload logic for all services |
| `SyncService+Download.swift` | Download/import logic |
| `SyncService+Process.swift` | QSO processing during sync |
| `SyncDebugLog.swift` | Sync debugging utilities |
| `ImportService.swift` | ADIF parsing, deduplication, QSO creation |
| `ImportService+External.swift` | External file import handling |
| `ADIFParser.swift` | ADIF format parser |
| `DeduplicationService.swift` | QSO deduplication logic |
| `ICloudMonitor.swift` | iCloud sync status monitoring |
| `DescriptionLookup.swift` | Human-readable descriptions for codes |
| `DescriptionLookup+DXCC.swift` | DXCC entity descriptions |
| `FetchedQSO.swift` | Intermediate QSO representation during fetch |
| `ChallengesClient.swift` | Challenges API client |
| `ChallengesError.swift` | Challenges-specific errors |
| `ChallengesSyncService.swift` | Challenge data synchronization (sources, fetching) |
| `ChallengesSyncService+Participation.swift` | Challenge participation, progress sync, leaderboards |
| `ChallengeProgressEngine.swift` | Challenge progress calculation |
| `ChallengeQSOMatcher.swift` | Match QSOs to challenge criteria |
| `BugReportService.swift` | Collects device/app info for bug reports |
| `CallsignAliasService.swift` | Manage current and previous callsigns for alias matching |

### Views - Dashboard (`CarrierWave/Views/Dashboard/`)
| File | Purpose |
|------|---------|
| `DashboardView.swift` | Main dashboard with stats grid and services list |
| `DashboardView+Actions.swift` | Dashboard action handlers (sync, clear data) |
| `DashboardView+Services.swift` | Services list builder and detail sheet builders |
| `DashboardHelperViews.swift` | Reusable dashboard components (StatBox, ActivityGrid, QSOStatistics) |
| `ServiceListView.swift` | Vertical stacked service list with status indicators |
| `ServiceDetailSheet.swift` | Service detail sheet for tap-through actions |
| `StatDetailView.swift` | Drilldown view for stat categories |
| `StatItemRow.swift` | Individual stat row with expandable QSOs |

### Views - Logs (`CarrierWave/Views/Logs/`)
| File | Purpose |
|------|---------|
| `LogsContainerView.swift` | Container with segmented picker for QSOs and POTA Uploads |
| `LogsListView.swift` | Searchable/filterable QSO list content |

### Views - POTA Activations (`CarrierWave/Views/POTAActivations/`)
| File | Purpose |
|------|---------|
| `POTAActivationsView.swift` | POTA activations grouped by park with upload |
| `POTAActivationsHelperViews.swift` | Helper views for POTA activations (rows, sheets) |
| `POTALogEntryRow.swift` | Individual POTA log entry display (legacy) |

### Views - Challenges (`CarrierWave/Views/Challenges/`)
| File | Purpose |
|------|---------|
| `ChallengesView.swift` | Main challenges tab |
| `BrowseChallengesView.swift` | Browse available challenges |
| `ChallengeDetailView.swift` | Single challenge detail view (for joined challenges) |
| `ChallengePreviewDetailView.swift` | Challenge preview before joining |
| `ChallengeDetailHelperViews.swift` | Challenge detail components |
| `ChallengeProgressCard.swift` | Progress visualization card |
| `LeaderboardView.swift` | Challenge leaderboard display |

### Views - Settings (`CarrierWave/Views/Settings/`)
| File | Purpose |
|------|---------|
| `SettingsView.swift` | Main settings navigation |
| `ServiceSettingsViews.swift` | QRZ/POTA/LoFi auth configuration |
| `CloudSettingsViews.swift` | iCloud sync settings |
| `HAMRSSettingsView.swift` | HAMRS connection settings |
| `LoTWSettingsView.swift` | LoTW login configuration |
| `ChallengesSettingsView.swift` | Challenges feature settings |
| `POTAAuthWebView.swift` | POTA OAuth WebView |
| `SyncDebugView.swift` | Sync debugging interface |
| `AttributionsView.swift` | Third-party attributions |
| `ExternalDataView.swift` | External data cache status and refresh (POTA parks) |
| `BugReportView.swift` | Bug report form with dpaste upload and Discord instructions |
| `CallsignAliasesSettingsView.swift` | Manage current and previous callsigns |
| `SettingsSections.swift` | Sync Sources section with service navigation links |

### Utilities (`CarrierWave/Utilities/`)
| File | Purpose |
|------|---------|
| `KeychainHelper.swift` | Secure credential storage |

## Building and Testing

**NEVER build, run tests, or use the iOS simulator yourself. Always prompt the user to do so.**

When you need to verify changes compile or tests pass, ask the user to run the appropriate command (e.g., `make build`, `make test`) and report back the results.

## Overview

Carrier Wave is a SwiftUI/SwiftData iOS app for amateur radio QSO (contact) logging with cloud sync to QRZ, POTA, and Ham2K LoFi.

## Quick Reference

| Area | Description | Details |
|------|-------------|---------|
| Architecture | Data models, services, view hierarchy | [docs/architecture.md](docs/architecture.md) |
| Setup | Development environment, build commands | [docs/SETUP.md](docs/SETUP.md) |
| Sync System | QRZ, POTA, LoFi integration | [docs/features/sync.md](docs/features/sync.md) |
| Statistics | Dashboard stats and drilldown views | [docs/features/statistics.md](docs/features/statistics.md) |

## Code Standards

- **Maximum file size: 1000 lines.** Refactor when approaching this limit.
- Use `actor` for API clients (thread safety)
- Use `@MainActor` for view-bound services
- Store credentials in Keychain, never in SwiftData
- Tests use in-memory SwiftData containers

## Linting & Formatting

Uses SwiftLint (`.swiftlint.yml`) and SwiftFormat (`.swiftformat`).

**Key limits:**
- Line length: 120 (warning), 200 (error)
- File length: 500 (warning), 1000 (error)
- Function body: 50 lines (warning), 100 (error)
- Type body: 300 lines (warning), 500 (error)
- Cyclomatic complexity: 15 (warning), 25 (error)

**Formatting rules:**
- 4-space indentation, no tabs
- LF line endings
- Trailing commas allowed
- `else` on same line as closing brace
- Spaces around operators and ranges
- Remove explicit `self` where possible
- Imports sorted, testable imports at bottom

## Getting Started

See [docs/SETUP.md](docs/SETUP.md) for device builds and additional commands.

## Version Updates

When releasing a new version, update **both** locations:

1. **Xcode project** (`CarrierWave.xcodeproj/project.pbxproj`):
   - `MARKETING_VERSION` - The user-facing version (e.g., "1.2.0")
   - `CURRENT_PROJECT_VERSION` - The build number (increment for each build)

2. **Settings view** (`CarrierWave/Views/Settings/SettingsView.swift`):
   - Update the hardcoded version string in the "About" section (~line 232)

## Issue Tracking

This project uses **bd** (beads). Work is NOT complete until `git push` succeeds.
