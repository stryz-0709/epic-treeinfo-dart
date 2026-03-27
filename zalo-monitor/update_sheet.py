import sys
import os
import gspread
import time
from google.oauth2.service_account import Credentials

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 update_sheet.py <access_token> <refresh_token>")
        return 1

    new_access_token = sys.argv[1]
    new_refresh_token = sys.argv[2]

    # Use relative path from this script's location
    SERVICE_ACCOUNT_FILE = os.path.join(os.path.dirname(__file__), '..', 'plate_detection_credentials.json')
    SHEET_URL = "https://docs.google.com/spreadsheets/d/1uCnIkjx8GzFgOkzbIIHOgunalvm81zrZv0aidZaYgOk"
    SHEET_TAB = 'APIKeys'

    try:
        scopes = ["https://www.googleapis.com/auth/spreadsheets", "https://www.googleapis.com/auth/drive"]
        creds = Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=scopes)
        client = gspread.authorize(creds)
        sheet_id = SHEET_URL.split('/d/')[1].split('/')[0]
        spreadsheet = client.open_by_key(sheet_id)
        worksheet = spreadsheet.worksheet(SHEET_TAB)

        worksheet.update_cell(2, 1, new_access_token)
        worksheet.update_cell(2, 2, new_refresh_token)
        worksheet.update_cell(2, 6, int(time.time()))
        print("Successfully updated sheet.")
        return 0
    except Exception as e:
        print(f"ERROR: Failed to write to the sheet: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
