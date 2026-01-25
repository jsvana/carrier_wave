# Architecture

## Data Models

Located in `CarrierWave/Models/`:

| Model | Purpose |
|-------|---------|
| **QSO** | Core contact record: callsign, band, mode, timestamp, grid squares, park reference, RST reports. Has `deduplicationKey` (2-minute buckets + band + mode + callsign) and `callsignPrefix` for DXCC entity extraction. |
| **SyncRecord** | Join table tracking upload status (pending/uploaded/failed) per QSO per destination (QRZ/POTA). Cascade deletes with QSO. |
| **UploadDestination** | Configuration for sync targets with enabled flag and last sync timestamp. |
| **POTAUploadAttempt** | Records POTA upload attempts with status, timestamp, and response details. |

## Services

Located in `CarrierWave/Services/`. All API clients use `actor` for thread safety.

| Service | Purpose |
|---------|---------|
| **QRZClient** | QRZ.com Logbook API. Session-based auth, ADIF upload via query params. |
| **POTAClient** | Parks on the Air API. Bearer token auth, multipart ADIF upload, groups QSOs by park reference. |
| **LoFiClient** | Ham2K LoFi sync. Email-based device linking, paginated operation/QSO fetching with `synced_since_millis`. |
| **ImportService** | ADIF parsing via ADIFParser, deduplication, creates QSO + SyncRecords. |
| **SyncService** | Orchestrates uploads to all destinations, batches QSOs (50 per batch for QRZ). |
| **KeychainHelper** | Secure credential storage. All auth tokens stored here, never in SwiftData. |
| **ADIFParser** | Parses ADIF format files into QSO records. |

## View Hierarchy

```
ContentView (TabView with AppTab enum for programmatic switching)
├── DashboardView - Activity grid, stats (tappable → StatDetailView), sync status
├── LogsListView - Searchable/filterable QSO list with delete
└── SettingsMainView - Auth flows (QRZ form, POTA WebView, LoFi email)
```

Dashboard stats use `QSOStatistics` struct with `items(for:)` method to group QSOs by category. `StatDetailView` shows expandable `StatItemRow` components with progressive QSO loading.

## Key Patterns

- **Credentials**: Stored in Keychain with service-namespaced keys (`qrz_*`, `pota_*`, `lofi_*`)
- **ADIF storage**: Raw ADIF kept in `rawADIF` field for reproducibility
- **Concurrency**: `@MainActor` classes for view-bound services, `actor` for API clients
- **Testing**: In-memory SwiftData containers for isolation

## File Organization

```
CarrierWave/
├── Models/           # SwiftData models
├── Services/         # API clients, sync logic
├── Views/
│   ├── Dashboard/    # Main dashboard and stats
│   ├── Logs/         # QSO list views
│   └── Settings/     # Configuration and auth
└── Utilities/        # Helpers (Keychain, etc.)
```
