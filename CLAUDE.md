# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

**Prefer using the `ios-simulator-skill` over running xcodebuild commands directly.** The skill provides optimized scripts for building, testing, and simulator management with minimal token output.

The commands below are provided as reference when the skill is not available:

```bash
# Build for simulator
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Build and install on device (device name: theseus)
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS,name=theseus' build
xcrun devicectl device install app --device theseus \
  ~/Library/Developer/Xcode/DerivedData/FullDuplex-*/Build/Products/Debug-iphoneos/FullDuplex.app
xcrun devicectl device process launch --device theseus com.jsvana.FullDuplex
```

## Architecture Overview

FullDuplex is a SwiftUI/SwiftData iOS app for amateur radio QSO (contact) logging with cloud sync to QRZ, POTA, and Ham2K LoFi.

### Data Models

- **QSO** - Core model: callsign, band, mode, timestamp, grid squares, park reference, RST reports. Has `deduplicationKey` (2-minute buckets + band + mode + callsign) and `callsignPrefix` for DXCC entity extraction.
- **SyncRecord** - Join table tracking upload status (pending/uploaded/failed) per QSO per destination (QRZ/POTA). Cascade deletes with QSO.
- **UploadDestination** - Configuration for sync targets with enabled flag and last sync timestamp.

### Services (all use `actor` for thread safety)

- **QRZClient** - QRZ.com Logbook API. Session-based auth, ADIF upload via query params.
- **POTAClient** - Parks on the Air API. Bearer token auth, multipart ADIF upload, groups QSOs by park reference.
- **LoFiClient** - Ham2K LoFi sync. Email-based device linking, paginated operation/QSO fetching with `synced_since_millis`.
- **ImportService** - ADIF parsing via ADIFParser, deduplication, creates QSO + SyncRecords.
- **SyncService** - Orchestrates uploads to all destinations, batches QSOs (50 per batch for QRZ).
- **KeychainHelper** - Secure credential storage. All auth tokens stored here, never in SwiftData.

### View Structure

```
ContentView (TabView with AppTab enum for programmatic switching)
├── DashboardView - Activity grid, stats (tappable → StatDetailView), sync status
├── LogsListView - Searchable/filterable QSO list with delete
└── SettingsMainView - Auth flows (QRZ form, POTA WebView, LoFi email)
```

Dashboard stats use `QSOStatistics` struct with `items(for:)` method to group QSOs by category. `StatDetailView` shows expandable `StatItemRow` components with progressive QSO loading.

### Key Patterns

- Credentials in Keychain (service-namespaced keys: `qrz_*`, `pota_*`, `lofi_*`)
- ADIF stored in `rawADIF` field for reproducibility
- `@MainActor` classes for view-bound services, `actor` for API clients
- Tests use in-memory SwiftData containers

## Issue Tracking

This project uses **bd** (beads). See AGENTS.md for workflow. Work is NOT complete until `git push` succeeds.
