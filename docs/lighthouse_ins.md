# Lighthouse CLI — Usage Guide

> Installed version: **13.0.3**  
> Requires: Node.js 22+ (currently running on Node 20 with warnings, works fine)  
> Chrome browser must be installed on the machine

---

## Quick Start

```bash
# Basic audit — generates HTML report and opens in browser
lighthouse http://localhost:3000 --view

# Audit a live site
lighthouse https://your-earthranger-dashboard.com --view
```

---

## Common Commands

### 1. Basic Audit (HTML report)

```bash
lighthouse http://localhost:3000 --output=html --view
```

### 2. Desktop Mode (recommended for dashboards)

```bash
lighthouse http://localhost:3000 --preset=desktop --output=html --view
```

### 3. JSON Output (for parsing with Python)

```bash
lighthouse http://localhost:3000 --preset=desktop --output=json --output-path=./lighthouse-report.json
```

### 4. Both HTML + JSON

```bash
lighthouse http://localhost:3000 --preset=desktop --output=json --output=html --output-path=./reports/dashboard
# Creates: ./reports/dashboard.report.html and ./reports/dashboard.report.json
```

### 5. Specific Categories Only

```bash
# Performance only
lighthouse http://localhost:3000 --preset=desktop --only-categories=performance --output=html --view

# Performance + Accessibility
lighthouse http://localhost:3000 --preset=desktop --only-categories=performance,accessibility --output=html --view

# Performance + Best Practices + Accessibility (skip SEO)
lighthouse http://localhost:3000 --preset=desktop --only-categories=performance,best-practices,accessibility --output=html --view
```

### 6. Headless (no browser window pops up)

```bash
lighthouse http://localhost:3000 --preset=desktop --chrome-flags="--headless" --output=html --output-path=./report.html
```

### 7. Quiet Mode (no console logs)

```bash
lighthouse http://localhost:3000 --preset=desktop --quiet --output=html --output-path=./report.html
```

### 8. Verbose Mode (debugging)

```bash
lighthouse http://localhost:3000 --preset=desktop --verbose --output=html --view
```

---

## Authenticated Pages (Login Required)

### Pass cookies

```bash
lighthouse http://localhost:3000/dashboard --preset=desktop --extra-headers="{\"Cookie\":\"sessionid=your_session_cookie_here\"}" --output=html --view
```

### Pass auth headers

```bash
lighthouse http://localhost:3000/dashboard --preset=desktop --extra-headers="{\"Authorization\":\"Bearer your_token_here\"}" --output=html --view
```

### From a JSON file

```bash
lighthouse http://localhost:3000/dashboard --preset=desktop --extra-headers=./auth-headers.json --output=html --view
```

Example `auth-headers.json`:

```json
{
  "Cookie": "sessionid=abc123; csrftoken=xyz456",
  "Authorization": "Bearer eyJhbGciOi..."
}
```

---

## Throttling Options

### No throttling (test real machine performance)

```bash
lighthouse http://localhost:3000 --preset=desktop --throttling-method=provided --screenEmulation.disabled --no-emulatedUserAgent --output=html --view
```

### Simulate slow network (4G mobile)

```bash
lighthouse http://localhost:3000 --throttling-method=simulate --output=html --view
```

---

## Output Formats

| Flag                          | Description                       |
| ----------------------------- | --------------------------------- |
| `--output=html`               | HTML report (default)             |
| `--output=json`               | JSON data (parseable with Python) |
| `--output=csv`                | CSV summary                       |
| `--output=json --output=html` | Both formats                      |
| `--output-path=./my-report`   | Custom output path                |
| `--view`                      | Auto-open HTML report in browser  |

---

## Category Reference

| Category       | Flag value       | What it checks                                              |
| -------------- | ---------------- | ----------------------------------------------------------- |
| Performance    | `performance`    | Load time, FCP, LCP, CLS, TBT, Speed Index                  |
| Accessibility  | `accessibility`  | ARIA, contrast, labels, keyboard nav                        |
| Best Practices | `best-practices` | HTTPS, console errors, deprecated APIs, image aspect ratios |
| SEO            | `seo`            | Meta tags, crawlability, structured data                    |

---

## Useful Flags Reference

| Flag                                       | Description                                  |
| ------------------------------------------ | -------------------------------------------- |
| `--preset=desktop`                         | Desktop configuration (no mobile throttling) |
| `--preset=perf`                            | Performance-focused preset                   |
| `--chrome-flags="--headless"`              | Run Chrome without UI                        |
| `--chrome-flags="--window-size=1920,1080"` | Custom window size                           |
| `--disable-full-page-screenshot`           | Skip screenshot (faster, smaller report)     |
| `--max-wait-for-load=45000`                | Wait up to 45s for page load                 |
| `--disable-storage-reset`                  | Don't clear cache before run                 |
| `--blocked-url-patterns="*.analytics.com"` | Block specific URLs                          |
| `--save-assets`                            | Save trace + devtools logs to disk           |
| `--locale=vi`                              | Vietnamese locale for report                 |

---

## Batch / Automation Examples

### Run from a .bat file

```bat
@echo off
echo Running Lighthouse audit...
lighthouse http://localhost:3000 --preset=desktop --output=json --output=html --output-path=./reports/dashboard_%DATE:~-4%%DATE:~3,2%%DATE:~0,2% --chrome-flags="--headless" --quiet
echo Done! Reports saved to ./reports/
```

### Parse JSON results with Python

```python
import json

with open("lighthouse-report.json", "r") as f:
    report = json.load(f)

categories = report["categories"]
for name, data in categories.items():
    print(f"{name}: {data['score'] * 100:.0f}/100")

# Access specific audits
fcp = report["audits"]["first-contentful-paint"]
print(f"First Contentful Paint: {fcp['displayValue']}")
```

---

## Lifecycle (Advanced)

```bash
# Step 1: Gather artifacts only (no audit)
lighthouse http://localhost:3000 -G

# Step 2: Audit from saved artifacts (no browser needed)
lighthouse http://localhost:3000 -A

# Both gather + audit, saving artifacts for later
lighthouse http://localhost:3000 -GA
```

---

## Troubleshooting

| Problem                    | Solution                                                                  |
| -------------------------- | ------------------------------------------------------------------------- |
| `EBADENGINE` warning       | Node 20 works but consider upgrading to Node 22 LTS                       |
| Chrome not found           | Set `CHROME_PATH` env variable to your Chrome executable                  |
| Connection refused         | Make sure the target server is running                                    |
| Timeout errors             | Increase `--max-wait-for-load=60000`                                      |
| Login page audited instead | Use `--extra-headers` to pass session cookies                             |
| Scores vary between runs   | Normal — run 3-5 times and average, or use `--throttling-method=simulate` |

---

## Version Info

```bash
lighthouse --version     # Check version
npm update -g lighthouse # Update to latest
npm list -g lighthouse   # Check installed location
```
