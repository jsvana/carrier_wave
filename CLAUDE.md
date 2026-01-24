# FullDuplex

> **IMPORTANT:** For general project context, read this file and linked docs.
> Only explore source files when actively implementing, planning, or debugging.

## Building and Testing

**NEVER build, run tests, or use the iOS simulator yourself. Always prompt the user to do so.**

When you need to verify changes compile or tests pass, ask the user to run the appropriate command (e.g., `make build`, `make test`) and report back the results.

## Overview

FullDuplex is a SwiftUI/SwiftData iOS app for amateur radio QSO (contact) logging with cloud sync to QRZ, POTA, and Ham2K LoFi.

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

## Getting Started

See [docs/SETUP.md](docs/SETUP.md) for device builds and additional commands.

## Issue Tracking

This project uses **bd** (beads). Work is NOT complete until `git push` succeeds.
