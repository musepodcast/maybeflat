# Contributing to Maybeflat

## Workflow

Use `main` as the stable branch.

Create short-lived branches for each change:

```powershell
git checkout main
git pull
git checkout -b feature/your-change
```

Commit in small, focused steps:

```powershell
git add .
git commit -m "Add eclipse subtype filter"
```

Push the branch and open a pull request:

```powershell
git push -u origin feature/your-change
```

After the pull request is merged:

```powershell
git checkout main
git pull
```

## Branch naming

Use one of these prefixes:

- `feature/...`
- `fix/...`
- `chore/...`
- `docs/...`

Examples:

- `feature/astronomy-events`
- `fix/event-picker-layout`
- `chore/release-v1.0.1`

## Pull requests

Keep each pull request scoped to one change area.

Before opening a pull request:

1. Rebase or merge the latest `main` into your branch.
2. Make sure the GitHub Actions checks pass.
3. Update `CHANGELOG.md` if the change matters to users or contributors.

## Versioning

This project uses semantic version tags:

- major: `v2.0.0`
- minor: `v1.1.0`
- patch: `v1.0.1`

Tag releases from `main` only.

Example:

```powershell
git checkout main
git pull
git tag -a v1.0.1 -m "Maybeflat v1.0.1"
git push origin v1.0.1
```

## Backend checks

The backend should stay compatible with the pinned dependencies in `backend_api/requirements.txt`.

Local backend validation:

```powershell
cd backend_api
.venv\Scripts\python.exe -m compileall app
```

## Flutter checks

Local Flutter validation:

```powershell
cd app_flutter
flutter pub get
flutter analyze
```

## Notes

- Do not commit local virtual environments.
- Do not commit generated build output.
- Keep `main` deployable and tag only known-good release points.
