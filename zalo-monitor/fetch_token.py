import json
import os
import sys
import time
import subprocess
from typing import Any, Dict, Optional, Tuple

import gspread
import requests
from google.oauth2.service_account import Credentials


class FlowError(Exception):
    pass


def load_credentials() -> Dict[str, Any]:
    path = os.path.join(os.path.dirname(__file__), "zalo_credentials.json")
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f) or {}
    except Exception:
        return {}


def get_config() -> Dict[str, Any]:
    creds = load_credentials()
    return {
        "SHEET_URL": os.getenv("SHEET_URL", creds.get("SHEET_URL")),
        "GET_OA_URL": os.getenv("GET_OA_URL", creds.get("GET_OA_URL")),
        "REFRESH_URL": os.getenv("REFRESH_URL", creds.get("REFRESH_URL")),
        "SHEET_TAB": os.getenv("SHEET_TAB", creds.get("SHEET_TAB", "APIKeys")),
        "OA_APP_ID": os.getenv("OA_APP_ID", creds.get("OA_APP_ID")),
        "OA_SECRET_KEY": os.getenv("OA_SECRET_KEY", creds.get("OA_SECRET_KEY")),
        "ZALO_GROUP_ID": os.getenv("ZALO_GROUP_ID", creds.get("ZALO_GROUP_ID")),
        "SERVICE_ACCOUNT_FILE": os.getenv("SERVICE_ACCOUNT_FILE", creds.get("SERVICE_ACCOUNT_FILE"),
        ),
    }


def save_tokens_to_credentials(
    access_token: Optional[str], refresh_token: Optional[str]
) -> None:
    path = os.path.join(os.path.dirname(__file__), "zalo_credentials.json")
    try:
        existing: Dict[str, Any] = {}
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                existing = json.load(f) or {}
        if access_token:
            existing["OA_ACCESS_TOKEN"] = access_token
        if refresh_token:
            existing["OA_REFRESH_TOKEN"] = refresh_token
        with open(path, "w", encoding="utf-8") as f:
            json.dump(existing, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def fetch_tokens_from_sheet(
    sheet_url: Optional[str], sheet_tab: str, service_account_file: str
) -> Tuple[str, str, Optional[str], Optional[str]]:
    if not sheet_url:
        raise FlowError("SHEET_URL is not provided.")

    try:
        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ]
        creds = Credentials.from_service_account_file(
            os.path.join(os.path.dirname(__file__), service_account_file),
            scopes=scopes,
        )
        client = gspread.authorize(creds)

        sheet_id = sheet_url.split("/d/")[1].split("/")[0]
        spreadsheet = client.open_by_key(sheet_id)
        worksheet = spreadsheet.worksheet(sheet_tab)

        row = worksheet.row_values(2)
        if not row or len(row) < 5:
            raise FlowError("Sheet response missing expected columns in row 2")

        access_token = row[0]
        refresh_token = row[1]
        app_id = row[3] if len(row) > 3 else None
        secret_key = row[4] if len(row) > 4 else None

        return access_token, refresh_token, app_id, secret_key

    except gspread.exceptions.SpreadsheetNotFound:
        raise FlowError("Spreadsheet not found. Check the URL and permissions.")
    except gspread.exceptions.WorksheetNotFound:
        raise FlowError(f"Worksheet '{sheet_tab}' not found in the spreadsheet.")
    except Exception as exc:
        raise FlowError(
            f"An error occurred while fetching tokens from the sheet: {exc}"
        ) from exc


def check_access_token(get_oa_url: str, access_token: str) -> bool:
    resp = requests.get(
        get_oa_url, headers={"access_token": access_token}, timeout=30
    )
    if not resp.ok:
        return False
    try:
        data = resp.json()
    except ValueError:
        return False
    return int(data.get("error", -1)) == 0


def refresh_access_token(
    refresh_url: str, app_id: str, secret_key: str, refresh_token: str
) -> Tuple[str, str]:
    form = {
        "refresh_token": refresh_token,
        "app_id": app_id,
        "grant_type": "refresh_token",
    }
    headers = {
        "secret_key": secret_key,
        "Content-Type": "application/x-www-form-urlencoded",
    }
    resp = requests.post(refresh_url, data=form, headers=headers, timeout=30)
    if not resp.ok:
        raise FlowError(f"Refresh HTTP {resp.status_code}: {resp.text}")
    try:
        data = resp.json()
    except ValueError:
        raise FlowError("Refresh returned non-JSON body")
    if not (data.get("access_token") and data.get("refresh_token")):
        raise FlowError(f"Refresh missing tokens: {data}")
    return data["access_token"], data["refresh_token"]


def get_zalo_access_token() -> str:
    cfg = get_config()
    required = ["SHEET_URL", "GET_OA_URL", "REFRESH_URL", "SERVICE_ACCOUNT_FILE"]
    missing = [k for k in required if not cfg.get(k)]
    if missing:
        raise FlowError(f"Missing required config: {', '.join(missing)}")

    # 1) Fetch tokens
    access_token, refresh_token, app_id, secret_key = fetch_tokens_from_sheet(
        cfg["SHEET_URL"],
        cfg.get("SHEET_TAB", "APIKeys"),
        cfg["SERVICE_ACCOUNT_FILE"],
    )
    if not app_id:
        app_id = cfg.get("OA_APP_ID")
    if not secret_key:
        secret_key = cfg.get("OA_SECRET_KEY")
    if not (access_token and refresh_token and app_id and secret_key):
        raise FlowError(
            "Sheet did not return required fields: access_token, refresh_token, app_id, secret_key"
        )

    # 2) Check token
    if check_access_token(cfg["GET_OA_URL"], access_token):
        save_tokens_to_credentials(access_token, None)
        return access_token

    # 3) Refresh token
    print("Access token invalid; refreshing...")
    new_access_token, new_refresh_token = refresh_access_token(
        cfg["REFRESH_URL"], app_id, secret_key, refresh_token
    )

    # 4) Update back to sheet by calling a separate script
    update_script_path = os.path.join(os.path.dirname(__file__), "update_sheet.py")
    result = subprocess.run(
        [
            sys.executable,  # Use current Python interpreter instead of "python3"
            update_script_path,
            new_access_token,
            new_refresh_token
        ],
        capture_output=True,
        text=True,
        check=False
    )
    if result.returncode != 0:
        # Log the error from the subprocess but raise a generic FlowError
        print(f"ERROR from update_sheet.py: {result.stderr.strip()}", file=sys.stderr)
        raise FlowError("Failed to update sheet via separate script.")
    
    print(result.stdout.strip()) # Print success message from subprocess
    save_tokens_to_credentials(new_access_token, new_refresh_token)
    
    return new_access_token


def main() -> int:
    try:
        access_token = get_zalo_access_token()
        print(json.dumps({"status": "success", "access_token": access_token}))
        return 0
    except FlowError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())