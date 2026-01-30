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

See [docs/FILE_INDEX.md](docs/FILE_INDEX.md) for the complete file-to-purpose mapping.

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

## Changelog

**Maintain the changelog incrementally as you work.** Do not construct it from git history.

**File:** `CHANGELOG.md`

**When to update:**
- After completing a feature (add to "Added" section)
- After fixing a bug (add to "Fixed" section)
- After making breaking or notable changes (add to "Changed" section)

**Format:** Follow [Keep a Changelog](https://keepachangelog.com/) conventions:

```markdown
## [Unreleased]

### Added
- New feature description

### Fixed
- Bug fix description

### Changed
- Notable change description
```

**Guidelines:**
- Write entries immediately after completing work, while context is fresh
- Use imperative mood ("Add feature" not "Added feature")
- Be specific but concise - one line per change
- Group related changes under a single bullet with sub-items if needed
- When releasing, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`

## Issue and feature ideas

I'll occasionally store human-generated plans/bugs/etc in `docs/plans/human` and `docs/bugs`. Look through these to find new work to do. Mark the documents as done in a way that you can easily find once they're completed.

## Git Workflow

**Do NOT use git worktrees.** All work should be done on the main branch or feature branches in the primary working directory.
