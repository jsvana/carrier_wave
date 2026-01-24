# Setup & Build Commands

## Build Commands

**Prefer using the `ios-simulator-skill` over running xcodebuild commands directly.** The skill provides optimized scripts for building, testing, and simulator management with minimal token output.

### Simulator Workflow

**Always rebuild and reinstall to test code changes.** Simply launching the app will run the old version.

```bash
# Full workflow: build, install, launch (use this after code changes)
python3 ~/.claude/skills/ios-simulator-skill/scripts/build_and_test.py --project FullDuplex.xcodeproj --scheme FullDuplex
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/FullDuplex-*/Build/Products/Debug-iphonesimulator/FullDuplex.app
python3 ~/.claude/skills/ios-simulator-skill/scripts/app_launcher.py --launch com.jsvana.FullDuplex

# If app is already running, terminate first
python3 ~/.claude/skills/ios-simulator-skill/scripts/app_launcher.py --terminate com.jsvana.FullDuplex
```

### Manual xcodebuild Commands

```bash
# Build for simulator
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### Device Build (device name: theseus)

```bash
# Build for device
xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex \
  -destination 'platform=iOS,name=theseus' build

# Install on device
xcrun devicectl device install app --device theseus \
  ~/Library/Developer/Xcode/DerivedData/FullDuplex-*/Build/Products/Debug-iphoneos/FullDuplex.app

# Launch on device
xcrun devicectl device process launch --device theseus com.jsvana.FullDuplex
```

## Required Xcode Configuration

### 1. iCloud Entitlements

In Xcode, select the FullDuplex target, go to "Signing & Capabilities", and add:

1. **iCloud** capability
   - Check "iCloud Documents"
   - Add container: `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`

2. **Background Modes** capability
   - Check "Background fetch"

### 2. Info.plist Entries (for ADIF file handling)

Add Document Types to support opening .adi and .adif files:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>ADIF Log File</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Default</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.amateur-radio-log</string>
        </array>
    </dict>
</array>
```
