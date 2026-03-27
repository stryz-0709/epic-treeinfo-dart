"""
Generate ranger accounts from CSV data.
Outputs: users.json (with bcrypt hashes) + accounts_export.csv (plaintext for distribution)
"""

import csv
import json
import os
import bcrypt

# ── Configuration ────────────────────────────────────────────
CSV_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "DS cap Account_can bo di tuan.csv")
USERS_FILE = os.path.join(os.path.dirname(__file__), "users.json")
EXPORT_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "accounts_export.csv")

# Leader positions (Đội trưởng, Đội phó, Trạm trưởng, Trạm phó)
LEADER_KEYWORDS = ["đội trưởng", "đội phó", "trạm trưởng", "trạm phó"]

REGION_MAP = {
    "Ea H'leo": "eahleo",
    "BJW": "bjw",
}


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()


def clean_phone(phone: str) -> str:
    """Remove spaces from phone number."""
    return phone.replace(" ", "").strip()


def is_leader(position: str) -> bool:
    pos_lower = position.lower()
    return any(kw in pos_lower for kw in LEADER_KEYWORDS)


def main():
    # Load existing users (keep admin)
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, "r", encoding="utf-8") as f:
            users = json.load(f)
    else:
        users = {}

    # Parse CSV
    rows = []
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            # Skip header rows and empty rows
            if len(row) < 5:
                continue
            stt = row[0].strip()
            if not stt.isdigit():
                continue
            rows.append({
                "stt": int(stt),
                "name": row[1].strip(),
                "position": row[2].strip(),
                "phone": clean_phone(row[3]),
                "region_raw": row[4].strip(),
            })

    # Generate accounts
    export_rows = []
    region_counters = {"eahleo": 0, "bjw": 0}

    for r in rows:
        region_key = REGION_MAP.get(r["region_raw"], r["region_raw"].lower())
        region_counters[region_key] = region_counters.get(region_key, 0) + 1
        idx = region_counters[region_key]

        username = f"{region_key}.{idx:02d}"
        password = r["phone"]  # phone number as password
        role = "leader" if is_leader(r["position"]) else "ranger"

        users[username] = {
            "password": hash_password(password),
            "role": role,
            "display_name": r["name"],
            "region": region_key,
            "position": r["position"],
            "phone": r["phone"],
        }

        export_rows.append({
            "stt": r["stt"],
            "username": username,
            "password": password,
            "name": r["name"],
            "position": r["position"],
            "role": role,
            "region": region_key,
            "phone": r["phone"],
        })

    # Save users.json
    with open(USERS_FILE, "w", encoding="utf-8") as f:
        json.dump(users, f, indent=2, ensure_ascii=False)
    print(f"✓ Saved {len(users)} users to {USERS_FILE}")

    # Save export CSV
    with open(EXPORT_FILE, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["stt", "username", "password", "name", "position", "role", "region", "phone"])
        writer.writeheader()
        writer.writerows(export_rows)
    print(f"✓ Exported {len(export_rows)} accounts to {EXPORT_FILE}")

    # Print summary
    leaders = sum(1 for r in export_rows if r["role"] == "leader")
    rangers = sum(1 for r in export_rows if r["role"] == "ranger")
    print(f"\nSummary:")
    print(f"  Ea H'leo: {region_counters['eahleo']} accounts")
    print(f"  BJW:      {region_counters['bjw']} accounts")
    print(f"  Leaders:  {leaders}")
    print(f"  Rangers:  {rangers}")
    print(f"\n{'STT':<5} {'Username':<12} {'Password':<14} {'Role':<8} {'Name'}")
    print("-" * 70)
    for r in export_rows:
        print(f"{r['stt']:<5} {r['username']:<12} {r['password']:<14} {r['role']:<8} {r['name']}")


if __name__ == "__main__":
    main()
