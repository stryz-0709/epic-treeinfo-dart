# Workspace Organization

Updated: 2026-03-18

## Goal

Import the V-Ranger mobile app into this workspace **without deleting** or replacing any existing EarthRanger web/dashboard assets.

## Current Layout

- `app/` → Existing EarthRanger web dashboard + API backend (unchanged)
- `zalo-monitor/` → Existing Zalo monitor service (unchanged)
- `data/`, `docs/`, `reports/`, `scripts/`, `tools/` → Existing supporting resources (unchanged)
- `mobile/epic-treeinfo-dart/` → Newly imported Flutter mobile app repository

## What Was Reorganized

- Added a new top-level `mobile/` container for mobile projects.
- Imported `https://github.com/stryz-0709/epic-treeinfo-dart` into `mobile/epic-treeinfo-dart/`.
- Kept all existing web/dashboard files in place to avoid breaking current flows.

## Notes

- No files were deleted.
- Existing project behavior and paths for the web dashboard remain preserved.

## Git Setup for V-Ranger Mobile Repo

- VS Code workspace setting added to auto-detect nested repositories:
  - `.vscode/settings.json`
- Root helper script added:
  - `git-vranger.ps1`
  - `git-vranger.cmd` (recommended on Windows for exact flag passthrough)

### Usage

- From workspace root, run `./git-vranger.cmd status -sb`.
- Use any Git command through the helper, for example:
  - `./git-vranger.cmd branch -a`
  - `./git-vranger.cmd checkout -b feature/my-change`
  - `./git-vranger.cmd fetch --all --prune`
  - `./git-vranger.cmd merge main`
