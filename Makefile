.PHONY: build build-device test devices install launch deploy clean lint format format-check setup-hooks

DEVICE_NAME := theseus
BUNDLE_ID := com.jsvana.FullDuplex
PROJECT := FullDuplex.xcodeproj
SCHEME := FullDuplex
SIMULATOR := iPhone 17 Pro

# Find the most recent DerivedData directory for this project
DERIVED_DATA = $(shell ls -td ~/Library/Developer/Xcode/DerivedData/FullDuplex-* 2>/dev/null | head -n1)

# Build for simulator (default)
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' build

# Build for device
build-device:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS,name=$(DEVICE_NAME)' build

# Run tests
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' test

# List available devices
devices:
	xcrun xctrace list devices

# Install app on device (requires build-device first)
install:
	xcrun devicectl device install app --device $(DEVICE_NAME) \
		"$(DERIVED_DATA)/Build/Products/Debug-iphoneos/FullDuplex.app"

# Launch app on device
launch:
	xcrun devicectl device process launch --device $(DEVICE_NAME) $(BUNDLE_ID)

# Build, install, and launch on device
deploy: build-device install launch

# Clean build artifacts
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/FullDuplex-*

# Lint Swift files
lint:
	swiftlint lint --strict

# Format Swift files
format:
	swiftformat .

# Check formatting without modifying files
format-check:
	swiftformat --lint .

# Setup pre-commit hooks (call from project root)
setup-hooks:
	@echo "Adding pre-commit script to git hooks..."
	@echo '#!/usr/bin/env bash' > .git/hooks/pre-commit.local
	@echo 'scripts/pre-commit.sh' >> .git/hooks/pre-commit.local
	@chmod +x .git/hooks/pre-commit.local
	@echo "Done. The bd hook will call scripts/pre-commit.sh"
	@echo ""
	@echo "To enable, add this to your bd pre-commit hook or run:"
	@echo "  ./scripts/pre-commit.sh"
