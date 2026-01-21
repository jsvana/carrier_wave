# Full Duplex Setup

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

### 3. Build and Run

After configuration, build and run on a device or simulator to test.
