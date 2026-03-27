"""
EarthRanger Alert Monitor
Polls EarthRanger for new alerts and sends notifications to Zalo
"""

import os
import json
import logging
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path
from threading import Thread, Event

from earthranger_client import EarthRangerClient, format_alert_message
from send_notification import deduplicator

# Import Zalo token management - try both import paths for compatibility
try:
    from utils.zalo.fetch_token import get_zalo_access_token, get_config, FlowError
except ImportError:
    from fetch_token import get_zalo_access_token, get_config, FlowError
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class EarthRangerAlertMonitor:
    """
    Monitors EarthRanger for new alerts and sends notifications to Zalo
    """
    
    def __init__(
        self,
        earthranger_domain: str,
        earthranger_token: str,
        poll_interval: int = 60,
        lookback_minutes: int = 5
    ):
        """
        Initialize the alert monitor
        
        Args:
            earthranger_domain: EarthRanger domain (e.g., 'yoursite.pamdas.org')
            earthranger_token: EarthRanger API token
            poll_interval: Seconds between API polls (default: 60)
            lookback_minutes: How far back to look for new alerts (default: 5)
        """
        self.client = EarthRangerClient(earthranger_domain, earthranger_token)
        self.poll_interval = poll_interval
        self.lookback_minutes = lookback_minutes
        self.stop_event = Event()
        self.processed_events = set()  # Track processed event IDs
        self.last_check = None
        
        # Load configuration
        self.config_path = Path(__file__).parent / "earthranger_config.json"
        self.config = self._load_config()
    
    def _load_config(self) -> dict:
        """Load or create default configuration"""
        default_config = {
            "enabled": True,
            "poll_interval": 60,
            "event_types": [],  # Empty = all types
            "event_categories": ["security"],  # Focus on security alerts
            "states": ["new", "active"],
            "min_priority": 0,  # 0 = all priorities
            "lookback_hours": 1,
            "zalo_enabled": True
        }
        
        if self.config_path.exists():
            try:
                with open(self.config_path, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults
                    for key, value in default_config.items():
                        config.setdefault(key, value)
                    return config
            except Exception as e:
                logger.warning(f"Error loading config: {e}, using defaults")
        
        # Save default config
        try:
            with open(self.config_path, 'w') as f:
                json.dump(default_config, f, indent=2)
        except Exception as e:
            logger.warning(f"Could not save default config: {e}")
        
        return default_config
    
    def _send_to_zalo(self, message: str) -> bool:
        """
        Send alert message to Zalo group
        
        Args:
            message: Message text to send
        
        Returns:
            True if sent successfully
        """
        if not self.config.get("zalo_enabled", True):
            logger.info("Zalo notifications disabled in config")
            return False
        
        try:
            # Get Zalo configuration
            zalo_config = get_config()
            group_id = (zalo_config.get("ZALO_GROUP_ID") or "").strip()
            if not group_id:
                logger.error("Zalo config missing: ZALO_GROUP_ID not set")
                return False
            
            # Get access token
            access_token = get_zalo_access_token()
            
            # Build payload
            payload = {
                "recipient": {"group_id": group_id},
                "message": {"text": message}
            }
            
            # Send message
            headers = {
                "access_token": access_token,
                "Content-Type": "application/json"
            }
            
            resp = requests.post(
                "https://openapi.zalo.me/v3.0/oa/group/message",
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if resp.status_code == 200:
                logger.info("EarthRanger alert sent to Zalo successfully")
                return True
            else:
                try:
                    err = resp.json()
                    logger.error(f"Zalo API error: {err}")
                except:
                    logger.error(f"Zalo API error: HTTP {resp.status_code}")
                return False
        
        except FlowError as exc:
            logger.error(f"Failed to acquire Zalo access token: {exc}")
            return False
        except Exception as e:
            logger.error(f"Error sending to Zalo: {e}")
            return False
    
    def _should_notify(self, event: dict) -> bool:
        """
        Check if event should trigger notification
        
        Args:
            event: Event dict from EarthRanger
        
        Returns:
            True if notification should be sent
        """
        event_id = event.get("id")
        
        # Skip if already processed
        if event_id in self.processed_events:
            return False
        
        # Check priority filter
        min_priority = self.config.get("min_priority", 0)
        event_priority = event.get("priority", 0)
        if event_priority < min_priority:
            logger.debug(f"Event {event_id} priority {event_priority} below threshold {min_priority}")
            return False
        
        # Check event type filter
        allowed_types = self.config.get("event_types", [])
        if allowed_types:
            event_type = event.get("event_type", "")
            if event_type not in allowed_types:
                logger.debug(f"Event type {event_type} not in allowed types")
                return False
        
        # Check event category filter
        allowed_categories = self.config.get("event_categories", [])
        if allowed_categories:
            event_category = event.get("event_category", {})
            category_value = event_category.get("value", "") if isinstance(event_category, dict) else ""
            if category_value not in allowed_categories:
                logger.debug(f"Event category {category_value} not in allowed categories")
                return False
        
        return True
    
    def check_alerts(self) -> int:
        """
        Check for new alerts and send notifications
        
        Returns:
            Number of alerts processed
        """
        try:
            # Determine time range
            if self.last_check:
                since = self.last_check
            else:
                lookback_hours = self.config.get("lookback_hours", 1)
                since = datetime.now(timezone.utc) - timedelta(hours=lookback_hours)
            
            # Get events
            states = self.config.get("states", ["new", "active"])
            result = self.client.get_events(
                state=states,
                updated_since=since,
                sort_by="-updated_at",
                page_size=100
            )
            
            events = result.get("results", [])
            logger.info(f"Found {len(events)} events since {since.isoformat()}")
            
            # Update last check time
            self.last_check = datetime.now(timezone.utc)
            
            # Process events
            processed_count = 0
            for event in events:
                if self._should_notify(event):
                    event_id = event.get("id")
                    
                    # Format and send notification
                    message = format_alert_message(event)
                    if self._send_to_zalo(message):
                        self.processed_events.add(event_id)
                        processed_count += 1
                        logger.info(f"Processed alert: {event.get('title', event_id)}")
                    
                    # Small delay between messages to avoid rate limiting
                    time.sleep(1)
            
            # Cleanup old processed events (keep last 1000)
            if len(self.processed_events) > 1000:
                self.processed_events = set(list(self.processed_events)[-500:])
            
            return processed_count
        
        except Exception as e:
            logger.error(f"Error checking alerts: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return 0
    
    def run(self):
        """
        Start the monitoring loop
        """
        logger.info(f"Starting EarthRanger alert monitor (poll interval: {self.poll_interval}s)")
        
        while not self.stop_event.is_set():
            try:
                if self.config.get("enabled", True):
                    processed = self.check_alerts()
                    if processed > 0:
                        logger.info(f"Processed {processed} new alerts")
                else:
                    logger.debug("Monitor disabled in config")
            
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")
            
            # Wait for next poll or stop signal
            self.stop_event.wait(self.poll_interval)
        
        logger.info("Alert monitor stopped")
    
    def start(self):
        """Start monitoring in background thread"""
        self.thread = Thread(target=self.run, daemon=True)
        self.thread.start()
        logger.info("Alert monitor started in background")
    
    def stop(self):
        """Stop the monitoring loop"""
        logger.info("Stopping alert monitor...")
        self.stop_event.set()
        if hasattr(self, 'thread'):
            self.thread.join(timeout=5)


def main():
    """Main entry point"""
    # Configuration - set these environment variables or modify directly
    EARTHRANGER_DOMAIN = os.getenv("EARTHRANGER_DOMAIN", "your-domain.pamdas.org")
    EARTHRANGER_TOKEN = os.getenv("EARTHRANGER_TOKEN", "your-token-here")
    POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "60"))  # seconds
    
    if EARTHRANGER_TOKEN == "your-token-here":
        print("=" * 60)
        print("EarthRanger Alert Monitor - Configuration Required")
        print("=" * 60)
        print("\nSet the following environment variables:")
        print("  EARTHRANGER_DOMAIN - Your EarthRanger domain (e.g., mysite.pamdas.org)")
        print("  EARTHRANGER_TOKEN  - Your API Bearer token")
        print("  POLL_INTERVAL      - Seconds between checks (default: 60)")
        print("\nOr edit the earthranger_config.json file after first run.")
        print("\nTo get your token:")
        print("  1. Log in to EarthRanger Admin Portal")
        print("  2. Create a long-lived API token")
        print("  See: https://support.earthranger.com/step-17-integrations-api-data-exports/creating-an-authentication-token")
        print("=" * 60)
        return
    
    # Create and run monitor
    monitor = EarthRangerAlertMonitor(
        earthranger_domain=EARTHRANGER_DOMAIN,
        earthranger_token=EARTHRANGER_TOKEN,
        poll_interval=POLL_INTERVAL
    )
    
    try:
        # Run in foreground
        monitor.run()
    except KeyboardInterrupt:
        print("\nShutting down...")
        monitor.stop()


if __name__ == "__main__":
    main()
