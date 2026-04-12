# Changelog

All notable changes to this project should be recorded in this file.

The format is intentionally simple and release-focused.

## [1.6.0] - 2026-04-12

Astronomy sky overlay release.

- Added sidereal-time star and zodiac constellation overlays driven by a client-side sky catalog
- Added constellation labels, full-sky guide mode, and star/constellation tap selection with focused highlights
- Added zodiac symbol and illustration rendering for selected constellations plus improved Polaris visibility
- Added astronomy playback and custom-time fixes so returning to current time resets the live view cleanly
- Removed the seeded North Pole marker so Polaris is easier to see at the center of the map

## [1.4.1] - 2026-04-11

Analyzer cleanup patch for the analytics release.

- Replaced deprecated admin dashboard dropdown initialization
- Switched web storage access from `dart:html` to `package:web`
- Added the `web` package dependency so Flutter analyze passes cleanly

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
