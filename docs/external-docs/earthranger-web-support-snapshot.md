# EarthRanger Web Support Snapshot

> Source root: https://support.earthranger.com/en_US/earthranger-web  
> Capture date: 2026-03-25  
> Type: Recursive, curated summary snapshot for agent retrieval

## Root Page Structure (`EarthRanger Web`)

The root page organizes support content into major areas:

- Login
- Main Page
- Web Settings
- Map Features
- Events
- Patrols
- Map Layers
- External Data Source
- Data Output
- Getting Help

## Key Linked Articles Captured

### Login & Profiles

- **Intro to Profiles in EarthRanger**
  - Profiles are PIN-based user identities, commonly used on shared devices.
  - Admin must configure profile users and PINs.
  - Separate guidance for mobile and web profile switching.

- **Log in to EarthRanger Web with a Username or Profile**
  - Username/password login flow.
  - Profile login flow from parent account dropdown.
  - Important logout behavior when profile mode is used.

- **Switch Between User Profiles with PINs on EarthRanger Web**
  - PIN is tied to profile and configured in admin.
  - Profile switching and return-to-parent flow required before full logout.

### Main Navigation & UI Basics

- **Explore the EarthRanger Main Page in EarthRanger Web**
  - Map View is central operational surface.
  - Main pieces: top navigation, map tools, map icons, menu.

- **Use the Top Navigation Bar in EarthRanger Web**
  - Protected area quicklinks.
  - Connection status indicator (health and realtime checks).
  - Messages, notifications, profile settings.

- **Use the EarthRanger Menu to Access Tools and Resources**
  - Entry point for alerts, support, and exports.
  - Linked to alert configuration and export guides.

- **Use Map Tools in EarthRanger Web to Navigate and Interact with Data**
  - Quick Add, basemaps, pin, ruler, print, time slider, zoom controls.

### Map Features, Icons, Layers

- **Understand Map Features in the EarthRanger Web Interface**
  - Icons, feature layers, analyzers, tracked subjects, map tools.
  - Layer visibility and configuration are site-dependent.

- **Identify and Interact with Icons in the EarthRanger Web Map View**
  - Icons represent subjects/devices/events.
  - Clicking icons opens details and actions.
  - Icon families are admin-controlled via feature/event configuration.

- **Get Started with Map Layers / Control Map Layers / Use Map Layer Controls**
  - Layer visibility toggles, hide/show all, sub-layer expand.
  - Search by layer names.
  - Per-layer actions: jump to location, tracks, heatmap.

### Events & Incidents

- **Understanding Events in EarthRanger Web**
  - Events are core incident/activity records.
  - Can stand alone, belong to patrols, or be grouped into incidents.

- **How to Create and Submit Events in EarthRanger Web**
  - Event creation paths: Events sidebar, map right-click, Quick Add.
  - Default fields include Reported by, priority, location, date/time, note, attachment.

- **Create Area-Based Event Locations in EarthRanger Web**
  - Polygon-based event areas supported when geometry type is polygon.
  - Shape must be closed and non-self-intersecting.

- **Organize Related Events with Incidents in EarthRanger Web**
  - Add new/existing events into incidents.
  - Incident priority/status and event expansion supported.

- **Manage Events and Incidents in EarthRanger Web**
  - Event feed anatomy, event detail sections (details/activity/history).
  - Incident creation from existing events or via nested event workflows.

### Patrols & Subjects

- **Explore Patrols Feed and Details in EarthRanger Web**
  - Patrols aggregate events, notes, media, tracks over time.
  - Patrol detail panel includes schedule, objective, tracks, activity timeline.

- **Create Patrols in EarthRanger Web**
  - Multiple creation entry points (patrol button, tracked subject context, map quick add).
  - Patrol type governs workflow and expected fields.

- **Monitor Movement of Subjects in EarthRanger Web**
  - Subject tracks and track-length configuration.
  - Multi-subject track visualization support.

### Filtering, Analysis, Visualization

- **Filter Events on EarthRanger Web**
  - Filter by state, priority, reporter, event types, date ranges.
  - Reset and map/feed synchronization behavior documented.

- **Analyze Movement and Activity Using Tools in EarthRanger Web**
  - Combined use of tracks, time slider, heatmaps for contextual analysis.

- **Visualize Temporal Changes with the Timeslider in EarthRanger Web**
  - Date-range replay of map data with presets and targeted analysis tips.

- **Visualize Activity with HeatMaps in EarthRanger Web**
  - Heatmap intensity tuning by sensitivity/radius.
  - Subject-level and layer-level activation options.

- **Customizing General Settings in EarthRanger Web**
  - App refresh persistence behavior.
  - Map display settings: clustering, labels, terrain, track points, inactive radios.

### Data Output & Support

- **Exporting Data from EarthRanger Web**
  - Subject KML/KMZ network link export.
  - Subject summary, observations, field events CSV flows.

- **Understanding ‘Tracked By’ vs ‘Reported By’ in EarthRanger Web**
  - Distinguishes patrol route ownership vs event reporter identity.
  - Dropdown management via Person subjects, permission set, event reporters.

- **Getting Help for EarthRanger**
  - Support email and ticketing paths.
  - Admin/peer support guidance.

### Related Admin/Advanced Pages Captured (cross-linked from web docs)

- Create/manage profiles in Admin
- Configure feature types and map styling
- Configure event types with schema-based setup
- Configure alerts
- API integration guidance page
- Immobility analyzer setup
- Exporting and preparing data

## Important Captured Cross-References

- EarthRanger API docs entry page: `step-17-integrations-api-data-exports/earthranger-api`
- Event schema authoring and event-type lifecycle
- Permission model implications for event categories
- Patrol + event coupling behaviors on mobile

## Capture Limitations

- Some support pages redirected through Helpjuice login middleware.
- Some pages exposed multilingual variants under alternate locale paths.
- Snapshot focuses on high-signal operational guidance and linked article summaries.

## URL Inventory (Seed + recursively fetched highlights)

- https://support.earthranger.com/en_US/earthranger-web
- https://support.earthranger.com/en_US/step-2-installation-login/profiles-login
- https://support.earthranger.com/en_US/step-2-installation-login/1803353-login
- https://support.earthranger.com/en_US/step-12-login-options-/profiles-web
- https://support.earthranger.com/en_US/step-3-navigation-basics/1803420-earthranger-main-page
- https://support.earthranger.com/en_US/step-3-navigation-basics/1859945-top-navigation-bar
- https://support.earthranger.com/en_US/step-3-navigation-basics/menu
- https://support.earthranger.com/en_US/step-3-navigation-basics/map-tools
- https://support.earthranger.com/en_US/step-3-navigation-basics/map-features
- https://support.earthranger.com/en_US/step-3-navigation-basics/icons
- https://support.earthranger.com/en_US/step-4-map-interface-navigation/map-layers
- https://support.earthranger.com/en_US/step-4-map-interface-navigation/using-map-layers
- https://support.earthranger.com/en_US/step-4-map-interface-navigation/controlling-the-map-window-using-map-layers-
- https://support.earthranger.com/en_US/step-5-tracking-devices-subjects-patrols/patrols-feed-web
- https://support.earthranger.com/en_US/step-5-tracking-devices-subjects-patrols/new-patrol
- https://support.earthranger.com/en_US/step-5-tracking-devices-subjects-patrols/tracked-subjects
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/reports
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/create-a-new-report
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/report-area-as-location
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/how-to-use-incidents
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/reports-incidents
- https://support.earthranger.com/en_US/step-9-data-visualization-and-event-filtering/filtering-reports
- https://support.earthranger.com/en_US/step-9-data-visualization-and-event-filtering/analysis-tools-
- https://support.earthranger.com/en_US/step-9-data-visualization-and-event-filtering/timeslider
- https://support.earthranger.com/en_US/step-9-data-visualization-and-event-filtering/about-heat-maps
- https://support.earthranger.com/en_US/step-9-data-visualization-and-event-filtering/settings
- https://support.earthranger.com/en_US/step-10-data-management-and-exporting/data-export-options
- https://support.earthranger.com/en_US/step-10-data-management-and-exporting/tracked-vs-reported-by
- https://support.earthranger.com/en_US/general-support-faqs/getting-help
- https://support.earthranger.com/en_US/step-17-integrations-api-data-exports/earthranger-api
