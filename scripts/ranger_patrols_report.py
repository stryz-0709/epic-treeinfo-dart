import os
import pandas as pd
import ecoscope
from datetime import datetime, timedelta

# --- CONFIGURATION ---------------------------------------------------------
# Replace these with your actual EarthRanger details
ER_SERVER = "https://epictech.pamdas.org"  # Your EarthRanger URL
ER_USERNAME = "epictechnologyjsc"
ER_PASSWORD = "@EPICTECH123"

# Set the date range you want to report on
# Adjust these dates as needed
START_DATE = "2026-01-1 01:00:00"
END_DATE = "2026-01-19 13:00:00"

# Output filename
OUTPUT_FILE = "ranger_patrols_details.csv"
# ---------------------------------------------------------------------------

def extract_patrol_details(row):
    """Extract detailed information from a patrol row."""
    details = {
        'patrol_id': row.get('id', ''),
        'name': row.get('objective', '') or row.get('title', '') or f"Patrol #{row.get('serial_number', '')}",
        'serial_number': row.get('serial_number', ''),
        'status': row.get('state', ''),
    }
    
    # Extract info from patrol_segments (first segment)
    segments = row.get('patrol_segments', [])
    if segments and len(segments) > 0:
        segment = segments[0]
        
        # Ranger/Leader name
        leader = segment.get('leader', {})
        if isinstance(leader, dict):
            details['ranger'] = leader.get('name', 'Unknown')
        else:
            details['ranger'] = 'Unassigned'
        
        # Patrol type
        details['patrol_type'] = segment.get('patrol_type', 'Unknown')
        
        # Time range
        time_range = segment.get('time_range', {})
        details['time_start'] = time_range.get('start_time', None)
        details['time_end'] = time_range.get('end_time', None)
        
        # If actual times are not available, use scheduled times
        if not details['time_start']:
            details['time_start'] = segment.get('scheduled_start', None)
        if not details['time_end']:
            details['time_end'] = segment.get('scheduled_end', None)
        
        # Start and end locations
        start_loc = segment.get('start_location', None)
        end_loc = segment.get('end_location', None)
        
        if start_loc and isinstance(start_loc, dict):
            details['start_location'] = f"{start_loc.get('latitude', '')}, {start_loc.get('longitude', '')}"
        elif start_loc:
            details['start_location'] = str(start_loc)
        else:
            details['start_location'] = 'N/A'
            
        if end_loc and isinstance(end_loc, dict):
            details['end_location'] = f"{end_loc.get('latitude', '')}, {end_loc.get('longitude', '')}"
        elif end_loc:
            details['end_location'] = str(end_loc)
        else:
            details['end_location'] = 'N/A'
    else:
        details['ranger'] = 'Unassigned'
        details['patrol_type'] = 'Unknown'
        details['time_start'] = None
        details['time_end'] = None
        details['start_location'] = 'N/A'
        details['end_location'] = 'N/A'
    
    # Calculate duration if both times are available
    if details['time_start'] and details['time_end']:
        try:
            start = pd.to_datetime(details['time_start'])
            end = pd.to_datetime(details['time_end'])
            duration = end - start
            total_minutes = int(duration.total_seconds() / 60)
            hours = total_minutes // 60
            minutes = total_minutes % 60
            details['duration'] = f"{hours}h {minutes}m"
        except:
            details['duration'] = 'N/A'
    else:
        details['duration'] = 'N/A'
    
    # Distance - this may need to be calculated from track data if available
    details['distance'] = 'N/A'  # Placeholder - actual distance requires track data
    
    return details


def generate_patrol_details_report():
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
    
    try:
        patrols_df = er_io.get_patrols(
            since=pd.Timestamp(START_DATE).isoformat(),
            until=pd.Timestamp(END_DATE).isoformat(),
            status=["active", "done", "cancelled"]
        )
    except Exception as e:
        print(f"Error fetching patrols: {e}")
        return

    if patrols_df.empty:
        print("No patrols found in this date range.")
        return

    print(f"   Found {len(patrols_df)} total patrols. Processing data...")

    # Extract details for each patrol
    patrol_details = []
    for idx, row in patrols_df.iterrows():
        details = extract_patrol_details(row)
        patrol_details.append(details)
    
    # Create report DataFrame
    report_df = pd.DataFrame(patrol_details)
    
    # Reorder columns for better readability
    column_order = [
        'serial_number',
        'name',
        'ranger',
        'patrol_type',
        'status',
        'time_start',
        'time_end',
        'duration',
        'start_location',
        'end_location',
        'distance'
    ]
    
    # Only include columns that exist
    column_order = [col for col in column_order if col in report_df.columns]
    report_df = report_df[column_order]
    
    # Sort by time_start
    report_df = report_df.sort_values(by='time_start', ascending=False)

    # --- EXPORT ---
    print(f"3. Saving report to {OUTPUT_FILE}...")
    report_df.to_csv(OUTPUT_FILE, index=False)
    
    print("Done! Here is a preview:")
    print(report_df.head(10).to_string())


if __name__ == "__main__":
    generate_patrol_details_report()
