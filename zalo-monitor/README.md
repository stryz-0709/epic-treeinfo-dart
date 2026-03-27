# Zalo Monitor

Standalone service that polls EarthRanger for new alerts and sends notifications to Zalo groups.

## Usage

```bash
python earthranger_monitor.py
```

## Configuration

Edit `earthranger_config.json` to configure:

- Poll interval
- Event types/categories/states to monitor
- Minimum priority level
- Lookback window

## Credentials

- `zalo_credentials.json` — Zalo app ID & secret
- `vienphudb-*.json` — Google service account key (for Sheets token storage)

> **Note:** Credential files should NOT be committed to git.
