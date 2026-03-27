import os
import pandas as pd
import ecoscope
from datetime import datetime, timedelta

# --- CONFIGURATION ---------------------------------------------------------
# Replace these with your actual EarthRanger details
ER_SERVER = "https://epictech.pamdas.org"  # Your EarthRanger URL
ER_USERNAME = "epictechnologyjsc"
ER_PASSWORD = "@EPICTECH123"

# Set the month you want to report on
# Example: 1st Jan 2023 to 1st Feb 2023
START_DATE = "2026-01-1 01:00:00"
END_DATE = "2026-01-19 13:00:00"

# Output filename
OUTPUT_FILE = "ranger_patrol_counts.csv"
# ---------------------------------------------------------------------------

def generate_patrol_report():
    print("1. Connecting to EarthRanger...")
    try:
        er_io = ecoscope.io.EarthRangerIO(
            server=ER_SERVER,
            username=ER_USERNAME,
            password=ER_PASSWORD
        )
    except Exception as e:
        print(f"Error connecting: {e}")
        return

    print(f"2. Fetching patrols from {START_DATE} to {END_DATE}...")
    
    # Fetch patrols within the date range
    # We use 'include_patrol_details=True' to ensure we get leader/member info
    try:
        patrols_df = er_io.get_patrols(
            since=pd.Timestamp(START_DATE).isoformat(),
            until=pd.Timestamp(END_DATE).isoformat(),
            status=["active", "done", "cancelled"] # Optional: filter by status if needed
        )
    except Exception as e:
        print(f"Error fetching patrols: {e}")
        return

    if patrols_df.empty:
        print("No patrols found in this date range.")
        return

    print(f"   Found {len(patrols_df)} total patrols. Processing data...")

    # --- DATA PROCESSING ---
    # The 'leader' column usually contains a dictionary (e.g., {'id': '...', 'name': 'John Doe'})
    # We need to extract just the name.
    
    def extract_leader_name(row):
        # Check if 'leader' column exists and is not null
        if 'leader' in row and row['leader'] is not None:
            # If it's a dictionary (standard ER format), get the name
            if isinstance(row['leader'], dict):
                return row['leader'].get('name', 'Unknown')
            return str(row['leader'])
        
        # Fallback: Sometimes leader info is deep inside 'patrol_segments'
        # This is a backup check if the top-level leader is missing
        if 'patrol_segments' in row and len(row['patrol_segments']) > 0:
            first_segment = row['patrol_segments'][0]
            if 'leader' in first_segment and first_segment['leader']:
                 return first_segment['leader'].get('name', 'Unknown')
                 
        return "Unassigned"

    # Apply the extraction function to create a clean 'Ranger Name' column
    patrols_df['Ranger Name'] = patrols_df.apply(extract_leader_name, axis=1)

    # --- COUNTING ---
    # Group by the Ranger Name and state, then count the number of rows (patrols)
    report_df = patrols_df.groupby(['Ranger Name', 'state']).size().reset_index(name='Patrol Count')
    report_df = report_df.rename(columns={'state': 'status'})

    # Sort by highest count first
    report_df = report_df.sort_values(by='Patrol Count', ascending=False)

    # --- EXPORT ---
    print(f"3. Saving report to {OUTPUT_FILE}...")
    report_df.to_csv(OUTPUT_FILE, index=False)
    
    print("Done! Here is a preview:")
    print(report_df.head())

if __name__ == "__main__":
    generate_patrol_report()