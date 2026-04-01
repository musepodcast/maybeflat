# Coastline Data

Maybeflat can load a real coastline dataset from:

`docs/data/coastlines.geojson`

Maybeflat can also load a separate country-boundary dataset from:

`docs/data/country_boundaries.geojson`

Maybeflat can also load a separate state/province-boundary dataset from:

`docs/data/state_boundaries.geojson`

Maybeflat can also load a separate real time-zone boundary dataset from:

`docs/data/timezone_boundaries.geojson`

The checked-in real time-zone dataset currently comes from:

`timezone-boundary-builder` `timezones-now.geojson.zip`

If that file exists, the backend scene endpoint uses it instead of the prototype continent polygons.

The checked-in default is currently a Natural Earth `10m` land GeoJSON.

Supported GeoJSON geometry types:

- `FeatureCollection`
- `Feature`
- `Polygon`
- `MultiPolygon`
- `LineString`
- `MultiLineString`
- `GeometryCollection`

Notes:

- Coordinates must be standard GeoJSON order: `[longitude, latitude]`
- Polygon holes are supported through multi-ring polygon rendering
- Very dense shapes are still simplified on the backend for `mobile`, are much less simplified for `desktop`, and are unsimplified for `full`
- Scene detail can be requested as `mobile`, `desktop`, or `full`
- country boundaries are rendered as stroked overlays on top of land masses when `country_boundaries.geojson` is present
- state/province boundaries are rendered as a separate stroked overlay when `state_boundaries.geojson` is present
- real civil time zones can be rendered from `timezone_boundaries.geojson` when that dataset is present
- These are real source coast coordinates, but the Maybeflat transform is still a custom flat-world model, not a conventional true-scale projection

Recommended next input:

- a coastline-only GeoJSON export from a GIS dataset
- or a land polygon GeoJSON file if you want filled continents
