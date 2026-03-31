# Flat World Model v0

This document defines the first internal geometry model for Maybeflat. It is not a claim about standard GIS truth. It is the project's own coordinate system for rendering, search, and measurement.

## Goals

- keep North Pole fixed at the center
- support a circular world boundary
- place Antarctica around the perimeter
- provide a consistent transform for UI, search, and distance tools
- work the same on phone and desktop

## Coordinate System

Each location is mapped from source latitude and longitude into a Maybeflat point:

- `radius_ratio`: normalized distance from the North Pole, from `0.0` to `1.0`
- `theta_degrees`: clockwise angle around the center
- `x`: normalized horizontal coordinate on the plane
- `y`: normalized vertical coordinate on the plane

## Latitude to Radius Rule

Version 0 uses a piecewise radial mapping:

- latitudes from `90` to `-60` map into the inner `85%` of the disk
- latitudes from `-60` to `-90` map into the outer `15%` ring

That lets Antarctica occupy the perimeter band instead of remaining a small southern landmass.

## Longitude to Angle Rule

Longitude becomes angle around the center:

- `0` degrees longitude is drawn at the top
- positive longitude rotates clockwise
- negative longitude rotates counterclockwise

## Distance Rule

Distance uses Euclidean plane distance between transformed points, not globe geodesics.

This is important because the app is modeling a flat coordinate plane, not a sphere.

## Known Limitations

- coastlines are not yet transformed from a real dataset
- the Antarctica ring is geometric, not dataset-derived
- search uses source coordinates until a full pipeline exists
- no claim is made that this is true scale under conventional cartography

## Upgrade Path

Next versions should add:

1. coastline ingestion and transform scripts
2. custom tile generation
3. label placement rules
4. alternate geometry presets for comparing different flat-world assumptions

## Current Dataset Hook

The backend now checks for a real coastline dataset at:

- `docs/data/coastlines.geojson`
- `docs/data/country_boundaries.geojson`

If present, those GeoJSON layers are transformed into the Maybeflat plane and used for land masses and political border strokes.
