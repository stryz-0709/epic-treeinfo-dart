"""
EarthRanger API Client
Fetches alerts/events from EarthRanger and sends to Zalo
"""

import logging
import requests
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)


class EarthRangerClient:
    """
    Client for interacting with EarthRanger API
    Documentation: https://support.earthranger.com/step-17-integrations-api-data-exports/earthranger-api
    """
    
    def __init__(self, domain: str, token: str):
        """
        Initialize EarthRanger client
        
        Args:
            domain: Your EarthRanger domain (e.g., 'yoursite.pamdas.org')
            token: Bearer token from EarthRanger Admin Portal
        """
        self.base_url = f"https://{domain}/api/v1.0"
        self.token = token
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
    
    def get_events(
        self,
        state: Optional[List[str]] = None,
        event_type: Optional[str] = None,
        event_category: Optional[str] = None,
        since: Optional[datetime] = None,
        until: Optional[datetime] = None,
        updated_since: Optional[datetime] = None,
        page: int = 1,
        page_size: int = 50,
        sort_by: str = "-updated_at",
        include_notes: bool = False,
        include_files: bool = False
    ) -> Dict[str, Any]:
        """
        Fetch events/alerts from EarthRanger
        
        Args:
            state: Filter by state(s): 'new', 'active', 'resolved'
            event_type: Filter by event type (e.g., 'wildlife_sighting_rep')
            event_category: Filter by category (e.g., 'security', 'monitoring')
            since: Start date/time for event_time
            until: End date/time for event_time
            updated_since: Filter events updated after this time
            page: Page number (default: 1)
            page_size: Results per page (default: 50, max: 4000)
            sort_by: Sort field, prefix with '-' for descending
            include_notes: Include event notes
            include_files: Include attached files
        
        Returns:
            Dict with 'count', 'next', 'previous', 'results' keys
        """
        params = {
            "page": page,
            "page_size": page_size,
            "sort_by": sort_by,
            "include_notes": str(include_notes).lower(),
            "include_files": str(include_files).lower()
        }
        
        # Add state filters (can be multiple)
        if state:
            for s in state:
                params.setdefault("state", []).append(s) if isinstance(params.get("state"), list) else None
            # For requests, we need to handle multiple values
            if len(state) == 1:
                params["state"] = state[0]
        
        if event_type:
            params["event_type"] = event_type
        if event_category:
            params["event_category"] = event_category
        if since:
            params["since"] = since.isoformat()
        if until:
            params["until"] = until.isoformat()
        if updated_since:
            params["updated_since"] = updated_since.isoformat()
        
        url = f"{self.base_url}/activity/events/"
        
        try:
            # Handle multiple state values
            if state and len(state) > 1:
                # Remove state from params, add manually to URL
                params.pop("state", None)
                state_params = "&".join([f"state={s}" for s in state])
                response = requests.get(
                    f"{url}?{state_params}",
                    headers=self.headers,
                    params=params,
                    timeout=30
                )
            else:
                response = requests.get(url, headers=self.headers, params=params, timeout=30)
            
            response.raise_for_status()
            return response.json()
        
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch events: {e}")
            raise
    
    def get_event(self, event_id: str) -> Dict[str, Any]:
        """
        Get a single event by ID
        
        Args:
            event_id: Event UUID
        
        Returns:
            Event details dict
        """
        url = f"{self.base_url}/activity/event/{event_id}/"
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch event {event_id}: {e}")
            raise
    
    def get_new_alerts(self, since: Optional[datetime] = None) -> List[Dict[str, Any]]:
        """
        Get new/active alerts (convenience method)
        
        Args:
            since: Only get alerts since this time
        
        Returns:
            List of alert events
        """
        result = self.get_events(
            state=["new", "active"],
            since=since,
            sort_by="-updated_at"
        )
        return result.get("results", [])
    
    def create_event(
        self,
        event_type: str,
        title: Optional[str] = None,
        priority: int = 0,
        state: str = "active",
        location: Optional[Dict[str, float]] = None,
        time: Optional[datetime] = None,
        reported_by: Optional[str] = None,
        event_details: Optional[Dict[str, Any]] = None,
        notes: Optional[List[Dict[str, str]]] = None,
    ) -> Dict[str, Any]:
        """
        Create a new event/report on EarthRanger

        Args:
            event_type: Event type value (e.g., 'wildlife_sighting_rep',
                        'fence_rep', 'fire_rep'). Use get_event_types() to
                        list available types.
            title: Optional event title. If omitted, EarthRanger auto-generates one.
            priority: Priority level (0=grey, 100=green, 200=amber, 300=red).
            state: Event state: 'new', 'active', or 'resolved'.
            location: Dict with 'latitude' and 'longitude' keys (WGS-84).
            time: Event time (UTC). Defaults to now.
            reported_by: Username or id of the reporter (optional).
            event_details: Dict of type-specific detail fields.
            notes: List of note dicts, each with a 'text' key.

        Returns:
            Created event dict from the API (includes generated 'id').
        """
        payload: Dict[str, Any] = {
            "event_type": event_type,
            "priority": priority,
            "state": state,
        }

        if title:
            payload["title"] = title
        if location:
            payload["location"] = {
                "latitude": location["latitude"],
                "longitude": location["longitude"],
            }
        if time:
            payload["time"] = time.isoformat()
        else:
            payload["time"] = datetime.now(timezone.utc).isoformat()
        if reported_by:
            payload["reported_by"] = reported_by
        if event_details:
            payload["event_details"] = event_details
        if notes:
            payload["notes"] = notes

        url = f"{self.base_url}/activity/events/"

        try:
            response = requests.post(
                url, headers=self.headers, json=payload, timeout=30
            )
            response.raise_for_status()
            created = response.json()
            logger.info(f"Created event: {created.get('id')} - {created.get('title')}")
            return created
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to create event: {e}")
            if hasattr(e, "response") and e.response is not None:
                logger.error(f"Response body: {e.response.text}")
            raise

    def get_event_types(self) -> List[Dict[str, Any]]:
        """
        Get all available event types
        
        Returns:
            List of event type definitions
        """
        url = f"https://{self.base_url.split('/api/')[0].split('://')[1]}/api/v2.0/activity/eventtypes/"
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            response.raise_for_status()
            data = response.json()
            return data.get("data", [])
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch event types: {e}")
            raise


def format_alert_message(event: Dict[str, Any]) -> str:
    """
    Format an EarthRanger event into a notification message
    
    Args:
        event: Event dict from EarthRanger API
    
    Returns:
        Formatted message string
    """
    title = event.get("title", "Alert")
    event_type = event.get("event_type", "unknown")
    state = event.get("state", "unknown")
    time_str = event.get("time", "")
    
    # Parse and format time
    if time_str:
        try:
            dt = datetime.fromisoformat(time_str.replace("Z", "+00:00"))
            time_formatted = dt.strftime("%Y-%m-%d %H:%M")
        except:
            time_formatted = time_str
    else:
        time_formatted = "N/A"
    
    # Get location if available
    location = event.get("location", {})
    lat = location.get("latitude", "N/A")
    lon = location.get("longitude", "N/A")
    
    # Get priority
    priority = event.get("priority", 0)
    priority_label = "🔴 Cao" if priority >= 300 else "🟡 Trung bình" if priority >= 100 else "🟢 Thấp"
    
    # Get event details
    details = event.get("event_details", {})
    details_str = ""
    if details:
        details_items = [f"  • {k}: {v}" for k, v in details.items() if v]
        if details_items:
            details_str = "\n" + "\n".join(details_items[:5])  # Limit to 5 items
    
    # Get reporter info
    reported_by = event.get("reported_by", {})
    reporter = reported_by.get("username", "N/A") if reported_by else "N/A"
    
    message = f"""🚨 CẢNH BÁO EARTHRANGER

📍 {title}
📋 Loại: {event_type}
⚡ Trạng thái: {state.upper()}
🎯 Ưu tiên: {priority_label}
🕐 Thời gian: {time_formatted}
📌 Vị trí: {lat}, {lon}
👤 Báo cáo bởi: {reporter}{details_str}"""
    
    return message


# Example usage and integration with Zalo
if __name__ == "__main__":
    import os
    from datetime import timedelta
    
    # Configuration - replace with your values
    EARTHRANGER_DOMAIN = os.getenv("EARTHRANGER_DOMAIN", "your-domain.pamdas.org")
    EARTHRANGER_TOKEN = os.getenv("EARTHRANGER_TOKEN", "your-token-here")
    
    # Initialize client
    client = EarthRangerClient(EARTHRANGER_DOMAIN, EARTHRANGER_TOKEN)
    
    # Get alerts from the last 24 hours
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    
    try:
        alerts = client.get_new_alerts(since=since)
        print(f"Found {len(alerts)} new/active alerts")
        
        for alert in alerts:
            message = format_alert_message(alert)
            print(message)
            print("-" * 50)
            
    except Exception as e:
        print(f"Error: {e}")
