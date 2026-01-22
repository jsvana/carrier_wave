# FullDuplex

An iOS app for amateur radio QSO (contact) logging with cloud synchronization to QRZ.com, Parks on the Air (POTA), and Ham2K LoFi.

## Features

- **QSO Logging** - Log contacts with callsign, band, mode, frequency, RST reports, grid squares, park references, and notes
- **Multi-Service Sync** - Upload QSOs to QRZ.com, POTA, and Ham2K LoFi with per-contact sync status tracking
- **ADIF Import/Export** - Import logs from other software with intelligent deduplication
- **Dashboard** - Activity statistics by band, mode, and country with drill-down views
- **POTA Integration** - Dedicated uploads view with park grouping and upload history

## Requirements

- iOS 17.0+
- Xcode 15.0+

## Building

```bash
# Build for simulator
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Architecture

Built with SwiftUI and SwiftData. No external dependencies.

### Project Structure

```
FullDuplex/
├── Models/          # QSO, sync records, POTA models
├── Services/        # API clients (QRZ, POTA, LoFi), sync orchestration
├── Views/           # Dashboard, logs list, settings, POTA uploads
└── Tests/           # Unit tests for parsers and clients
```

### Key Patterns

- **Actor-based clients** for thread-safe network operations
- **Keychain storage** for credentials (never stored in SwiftData)
- **Deduplication** via 2-minute time buckets + band + mode + callsign
- **Batch uploads** (50 QSOs per batch for QRZ, park-grouped for POTA)

## Sync Services

| Service | Auth Method | Features |
|---------|-------------|----------|
| QRZ.com | Session-based | Batch ADIF upload |
| POTA | Bearer token | Park-grouped multipart upload |
| Ham2K LoFi | Email device linking | Bidirectional sync |

## License

MIT License. See [LICENSE](LICENSE) for details.
