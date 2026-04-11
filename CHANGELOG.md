# Changelog

All notable changes to this project should be recorded in this file.

The format is intentionally simple and release-focused.

## [1.4.0] - 2026-04-11

Production analytics and admin operations release.

- Added Postgres-backed analytics storage for visitors, sessions, events, and request logs
- Added backend request telemetry and suspicious repeated-IP detection for traffic review and abuse visibility
- Added a protected `/admin` dashboard for traffic, feature usage, recent requests, recent sessions, and suspicious IP activity
- Added frontend event tracking for meaningful product actions including settings, astronomy usage, city search, and route measurement
- Added Postgres and admin-token wiring to the Docker production and home-hosting stacks
- Updated the home-hosting workflow to use local port `8081`

## [1.0.0] - 2026-03-30

Initial public baseline for `maybeflat`.

- Added the Flutter desktop/mobile client for the circular flat-world map
- Added the FastAPI backend for transforms, measurements, scenes, and tiles
- Added coastline, country-boundary, and state/province-boundary support
- Added astronomy overlays with sun path, moon path, lighting, and moon phase
- Added eclipse event browsing with next/previous event navigation
- Added git baseline and release tag `v1.0.0`
