# Home Release Workflow

This workflow is for your two-folder Windows setup:

- `maybeflat_dev` = where you make code changes
- `maybeflat` = the live home-hosted production clone

The goal is one command from `maybeflat_dev` that:

1. stages all changes
2. commits them
3. pushes `main` to GitHub
4. optionally pushes a tag
5. updates the production clone
6. runs `deploy_home.ps1` in production

## Script

Use:

- `ship_home.ps1`

## Folder Layout

Example:

```text
C:\Users\isaac\
  maybeflat\
  maybeflat_dev\
```

Put `ship_home.ps1` in `maybeflat_dev`.

The script assumes the production clone is the sibling folder `..\maybeflat` unless you override it.

## Basic Usage

From PowerShell inside `maybeflat_dev`:

```powershell
.\ship_home.ps1 -Message "Update home hosting and deployment flow"
```

With a tag:

```powershell
.\ship_home.ps1 -Message "Beta release" -Tag "v0.1.0"
```

With an explicit production path:

```powershell
.\ship_home.ps1 -Message "Update map UI" -ProductionPath "..\maybeflat"
```

## What The Script Checks

The script refuses to run unless:

- you are on branch `main`
- the production folder exists
- the production folder is a git repo
- the production repo has no local changes
- `.env.home` exists in the production repo
- both repos point at the same `origin`
- there are actual changes to ship

That is deliberate. It prevents you from accidentally deploying from the wrong branch or overwriting local production edits.

## Recommended Habit

- do all work in `maybeflat_dev`
- never edit code in `maybeflat`
- keep `.env.home` only in `maybeflat`
- use `.\ship_home.ps1 -Message "..."` when you want to publish

## If A Ship Fails

If the script fails before the push step, production is unchanged.

If it fails after the GitHub push step but before the production deploy step, GitHub will be ahead of production. In that case:

```powershell
cd ..\maybeflat
git pull --ff-only origin main
.\deploy_home.ps1
```
