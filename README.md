# Maybeflat

Maybeflat is a cross-platform mapping project built around a north-centered flat-world model. The app targets phone and desktop, renders the world as a circular plane, and treats Antarctica as the outer boundary ring.

This repository starts with:

- a Flutter app shell for the interactive client
- a FastAPI backend for flat-world transforms and measurements
- docs that define the geometry assumptions for the first prototype

## Project Shape

```text
maybeflat/
  app_flutter/
  backend_api/
  docs/
```

## Current Model Assumptions

- North Pole is the center of the map.
- Latitude is converted into radial distance from the center.
- Longitude is converted into angle around the center.
- Antarctica is forced into the outer band of the map instead of using standard globe geometry.
- Distances in the app are measured on the Maybeflat plane, not with great-circle math.

The model is intentionally custom. Standard globe projections may be used as source input, but not as the app's authoritative geometry.

## Getting Started

### Backend

Use Python 3.11 or 3.12 for the backend. The current dependency pins do not install cleanly on Python 3.14.

```powershell
cd backend_api
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8002
```

If your default `python` command points somewhere else, set `MAYBEFLAT_PYTHON` before running the root script:

```powershell
$env:MAYBEFLAT_PYTHON = 'C:\Path\To\python.exe'
.\start_backend.ps1
```

The root script also checks common standard install paths such as `C:\Users\<you>\AppData\Local\Programs\Python\Python312\python.exe` if `python` is not available on `PATH`.

API root: `http://127.0.0.1:8002`

### Flutter App

The Flutter CLI was not responsive in this environment, so the repo includes a hand-written starter app structure. Once Flutter is behaving normally, generate the missing platform folders inside `app_flutter`:

```powershell
cd app_flutter
flutter create . --platforms=android,ios,windows,linux,macos,web
flutter pub get
flutter run
```

The Dart source is already in place under `app_flutter/lib`.

## Quick Start Scripts

From the repo root:

```powershell
.\start_backend.ps1
.\start_flutter.ps1
```

The Flutter client is configured to call `http://127.0.0.1:8002` by default.

## Next Build Steps

1. Replace the seeded markers with backend-fed search results.
2. Add a tile or vector rendering layer for coastlines and political boundaries.
3. Build a real dataset transform pipeline for coastlines, labels, and the Antarctica perimeter ring.
4. Add project save/load, route plotting, and measurement history.
