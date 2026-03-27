# Patrol + Events Schema Snapshot

- Generated at (UTC): `2026-03-26T06:25:27.482025+00:00`
- EarthRanger domain: `epictech.pamdas.org`

## Fetch status

- ✅ All configured schema fetches completed successfully.

## Event type coverage

- v1 event types: **32**
- v2 event types: **5**

## Event schema field catalog

| Event Type | Version | Fields | Required | Parser |
|---|---:|---:|---:|---|
| `accident_rep` | `v1` | 3 | 0 | `v1-schema` |
| `activity_rep` | `v1` | 4 | 0 | `v1-schema` |
| `arrest_rep` | `v1` | 10 | 0 | `raw-string-fallback` |
| `confiscation_rep` | `v1` | 4 | 0 | `raw-string-fallback` |
| `contact_rep` | `v1` | 9 | 0 | `raw-string-fallback` |
| `fire_rep` | `v1` | 3 | 0 | `raw-string-fallback` |
| `firms_rep` | `v1` | 6 | 0 | `v1-schema` |
| `geofence_break` | `v1` | 8 | 0 | `v1-schema` |
| `gfw_activefire_alert` | `v1` | 9 | 0 | `v1-schema` |
| `gfw_glad_alert` | `v1` | 4 | 0 | `v1-schema` |
| `gfwfirealert` | `v1` | 2 | 0 | `v1-schema` |
| `gfwgladalert` | `v1` | 1 | 0 | `v1-schema` |
| `hwc_rep` | `v1` | 8 | 0 | `raw-string-fallback` |
| `immobility` | `v1` | 6 | 0 | `v1-schema` |
| `immobility_all_clear` | `v1` | 6 | 0 | `v1-schema` |
| `incident_collection` | `v1` | 3 | 0 | `raw-string-fallback` |
| `low_speed_percentile` | `v1` | 6 | 0 | `v1-schema` |
| `low_speed_wilcoxon` | `v1` | 4 | 0 | `v1-schema` |
| `low_speed_wilcoxon_all_clear` | `v1` | 5 | 0 | `v1-schema` |
| `medevac_rep` | `v1` | 10 | 0 | `raw-string-fallback` |
| `poacher_camp_rep` | `v1` | 3 | 0 | `raw-string-fallback` |
| `proximity` | `v1` | 8 | 0 | `v1-schema` |
| `rainfall_rep` | `v1` | 2 | 0 | `v1-schema` |
| `shot_rep` | `v1` | 7 | 0 | `raw-string-fallback` |
| `silence_source_provider_rep` | `v1` | 3 | 0 | `v1-schema` |
| `silence_source_rep` | `v1` | 7 | 0 | `v1-schema` |
| `sit_rep` | `v1` | 3 | 0 | `v1-schema` |
| `snare_rep` | `v1` | 4 | 0 | `raw-string-fallback` |
| `spoor_rep` | `v1` | 5 | 0 | `raw-string-fallback` |
| `subject_proximity` | `v1` | 10 | 0 | `v1-schema` |
| `traffic_rep` | `v1` | 7 | 0 | `raw-string-fallback` |
| `wildlife_sighting_rep` | `v1` | 3 | 0 | `raw-string-fallback` |
| `all_posts_check` | `v2` | 5 | 0 | `v2-json` |
| `deforestation_rep` | `v2` | 7 | 2 | `v2-json` |
| `land_grabbing_rep2` | `v2` | 6 | 0 | `v2-json` |
| `patrol_info_rep` | `v2` | 4 | 3 | `v2-json` |
| `tree_rep` | `v2` | 7 | 3 | `v2-json` |

## Patrol schema coverage

- Patrol types count: **5**
- Patrol samples used for field inventory: **5**

### Patrol field inventory

- **patrol_fields** (10): `files`, `id`, `notes`, `objective`, `patrol_segments`, `priority`, `serial_number`, `state`, `title`, `updates`
- **segment_fields** (12): `end_location`, `events`, `icon_id`, `id`, `image_url`, `leader`, `patrol_type`, `scheduled_end`, `scheduled_start`, `start_location`, `time_range`, `updates`
- **segment_time_range_fields** (2): `end_time`, `start_time`
- **segment_leader_fields** (13): `additional`, `common_name`, `content_type`, `created_at`, `id`, `image_url`, `is_active`, `name`, `subject_subtype`, `subject_type`, `tracks_available`, `updated_at`, `user`
- **segment_start_location_fields** (2): `latitude`, `longitude`
- **segment_end_location_fields** (2): `latitude`, `longitude`

## Stored artifact files

- `patrol-events-schema-snapshot-<date>.json` (full raw + normalized schema snapshot)
- `patrol-events-schema-snapshot-latest.json` (rolling latest)
- `patrol-events-schema-catalog-<date>.md` (human-readable summary)
- `patrol-events-schema-catalog-latest.md` (rolling latest)
