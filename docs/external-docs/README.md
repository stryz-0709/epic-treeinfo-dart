# External Documentation Snapshots for Agent Context

This folder contains locally saved documentation snapshots requested on **2026-03-25** so repository agents can scan and reference external EarthRanger/Ecoscope material without re-browsing every source manually.

## Source URLs

1. https://support.earthranger.com/en_US/earthranger-web
2. https://epictech.pamdas.org/api/v1.0/docs/interactive/
3. https://ecoscope.io/en/latest/index.html

## Saved Files

- `index.md`  
  Directory index + per-article topic tags for fast agent retrieval.

- `patrol-events-dashboard-context-fetch.md`  
  Focused, project-aligned extraction for patrol/events dashboards (event_type schema, event_details contract, patrol sync strategy, backend mapping notes).

- `earthranger-web-support-snapshot.md`  
  Curated snapshot of EarthRanger Web support hub content + recursively fetched linked help articles.

- `earthranger-api-epictech-snapshot.md`  
  Snapshot of EarthRanger API interactive docs and related API guidance/resources.

- `ecoscope-docs-snapshot.md`  
  Snapshot of Ecoscope documentation home, GUI docs, notebooks hub, and reachable linked pages.

## Notes on Capture Completeness

- A recursive fetch pass was performed on linked pages discovered from the original URLs.
- Some pages were inaccessible to automated fetch due to source-side restrictions:
  - `HTTP 403` on several Ecoscope notebook leaf pages.
  - parsing failure on `https://epictech.pamdas.org/api/v1.0/api-schema/`.
  - redirect/login pages for some support URLs.
- These inaccessible pages are still listed in the snapshot files for manual follow-up if needed.

## How agents should use these files

- Start with this folder before doing broad web fetches.
- Use the per-source snapshot files for:
  - endpoint discovery,
  - onboarding workflows,
  - EarthRanger field/UI behavior references,
  - Ecoscope capability and notebook navigation references.
