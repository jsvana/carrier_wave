# Sync System

FullDuplex syncs QSO logs to three cloud services: QRZ.com, Parks on the Air (POTA), and Ham2K LoFi.

## Sync Destinations

### QRZ.com

- **Auth**: Username/password → session key
- **Upload**: ADIF via query params, batched (50 QSOs per request)
- **Keychain keys**: `qrz_username`, `qrz_password`, `qrz_session_key`

### Parks on the Air (POTA)

- **Auth**: OAuth via WebView → bearer token
- **Upload**: Multipart ADIF, grouped by park reference
- **Keychain keys**: `pota_token`
- **Special handling**: QSOs with `myParkReference` are grouped and uploaded per-park

### Ham2K LoFi

- **Auth**: Email-based device linking
- **Sync**: Bidirectional - imports operations/QSOs, exports local changes
- **Uses**: `synced_since_millis` for incremental sync
- **Keychain keys**: `lofi_*`

## Data Flow

```
ADIF Import → ADIFParser → ImportService → QSO + SyncRecord (pending)
                                              ↓
                                         SyncService
                                              ↓
                              ┌───────────────┼───────────────┐
                              ↓               ↓               ↓
                          QRZClient      POTAClient      LoFiClient
                              ↓               ↓               ↓
                         SyncRecord status updated to uploaded/failed
```

## SyncRecord States

| Status | Meaning |
|--------|---------|
| `pending` | Awaiting upload |
| `uploaded` | Successfully synced |
| `failed` | Upload failed (will retry) |

## Key Implementation Details

- **Deduplication**: `QSO.deduplicationKey` uses 2-minute time buckets + band + mode + callsign
- **ADIF preservation**: Original ADIF stored in `rawADIF` for reproducibility
- **Batching**: QRZ uploads batched at 50 QSOs; POTA grouped by park
- **Error handling**: Failed uploads create `POTAUploadAttempt` records for debugging

## Related Plans

- [Sync Model Redesign](../plans/2026-01-21-sync-model-redesign.md)
- [QRZ Token Sync Design](../plans/2026-01-21-qrz-token-sync-design.md)
