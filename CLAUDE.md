# FullDuplex

> **IMPORTANT:** For general project context, read this file and linked docs.
> Only explore source files when actively implementing, planning, or debugging.

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
