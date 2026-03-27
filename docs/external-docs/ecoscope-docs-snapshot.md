# Ecoscope Documentation Snapshot

> Seed source: https://ecoscope.io/en/latest/index.html  
> Capture date: 2026-03-25  
> Type: Recursive, curated summary for agent context

## Ecoscope Home Highlights

Ecoscope is presented as a Python library for wildlife movement, environmental, and conservation analysis workflows.

Core capability areas referenced on the home page include:

- Data I/O (EarthRanger, GEE, Movebank, etc.)
- Movement analytics (relocations, trajectories, home ranges, resampling)
- Visualization
- Environmental analyses
- Covariate labeling

Additional project context shown:

- Development/testing guidance
- BSD 3-Clause licensing statement
- Acknowledgments and maintainer/support notes

## Ecoscope GUI Page (`ecoscope_gui.html`)

Captured sections:

- **Features**
  - Download events or subject-group observations from EarthRanger
  - Export to `.gpkg` and `.csv`
  - Multi-language UI support (English, French, Spanish)
  - Built with Python + Qt, using `ecoscope` processing under the hood

- **Requirements**
  - Windows/macOS/Linux system guidance
  - Platform-specific disk/memory expectations

- **Downloads**
  - Platform-specific artifacts for Windows, macOS (Apple Silicon + Intel), Linux
  - SHA-256 checksum guidance
  - macOS quarantine removal step documented (`xattr -dr ...`)

- **Screenshots**
  - UI screenshots for event and subject-group download flows

## Notebooks Hub (`notebooks.html`)

Notebook index captured with links to:

1. `01. IO`
2. `02. Relocations & Trajectories`
3. `03. Home Range & Movescape`
4. `04. EcoMap & EcoPlot`
5. `05. Environmental Analyses`
6. `06. Data Management`

### Successfully fetched notebook detail page

- `06. Data Management`
  - Contains a child link to `Tracking Data Gantt Chart`

## Additional linked pages observed

- `https://ecoscope.io/en/latest/index.html`
- `https://ecoscope.io/en/latest/ecoscope_gui.html`
- `https://ecoscope.io/en/latest/notebooks.html`
- `https://ecoscope.io/en/latest/notebooks/06.%20Data%20Management.html`
- `https://ecoscope.io/en/latest/notebooks/06.%20Data%20Management/Tracking%20Data%20Gantt%20Chart.html` (link discovered)

## Capture limitations

- `HTTP 403` occurred when fetching multiple notebook leaf pages:
  - `01. IO`
  - `02. Relocations & Trajectories`
  - `03. Home Range & Movescape`
  - `04. EcoMap & EcoPlot`
  - `05. Environmental Analyses`
- `https://ecoscope.io/en/latest/sitemap.xml` returned `HTTP 403`.

## Agent Usage Notes

For downstream tasks, agents can:

- use this file to discover available Ecoscope documentation sections,
- start with `ecoscope_gui.html` for operational GUI workflows,
- use the notebooks index as canonical navigation for analysis examples,
- perform manual/browser fetch for the notebook pages blocked by automated retrieval.
