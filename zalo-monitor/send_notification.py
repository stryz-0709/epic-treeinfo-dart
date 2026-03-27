"""
Zalo Notification Module with Deduplication
Sends real-time detection alerts to Zalo group with 60s deduplication window
"""

import logging
import time
import requests
from threading import Lock
from datetime import datetime

# Import Zalo token management
from utils.zalo.fetch_token import get_zalo_access_token, get_config, FlowError

logger = logging.getLogger(__name__)


class NotificationDeduplicator:
    """
    Deduplicates notifications based on camera_id, tracking_id, and direction
    60-second time window to avoid spam from stationary objects
    """
    
    def __init__(self, ttl_seconds=2):
        """
        Initialize deduplicator
        
        Args:
            ttl_seconds: Time window for deduplication (default 2s for Camera 3)
        """
        self.ttl_seconds = ttl_seconds
        self.notifications = {}  # key -> timestamp
        self.lock = Lock()
    
    def _make_key(self, camera_id, tracking_id, direction):
        """Generate deduplication key"""
        # For cameras 4-16: use camera_id only (no tracking)
        if tracking_id is None:
            return f"{camera_id}_simple"
        return f"{camera_id}_{tracking_id}_{direction}"
    
    def should_send(self, camera_id, tracking_id=None, direction=None):
        """
        Check if notification should be sent
        
        Args:
            camera_id: Camera identifier
            tracking_id: Optional tracking ID (for Cam 3)
            direction: Optional direction (IN/OUT for Cam 3)
        
        Returns:
            True if notification should be sent, False if duplicate
        """
        # Camera-specific TTL: 10 minutes (600s) for cameras 4-16, 60s for Camera 3
        ttl = 600 if (4 <= camera_id <= 16) else self.ttl_seconds
        
        with self.lock:
            key = self._make_key(camera_id, tracking_id, direction)
            current_time = time.time()
            
            # Clean up expired entries - must use the MAX ttl to avoid premature cleanup
            # Otherwise, camera 4-17 entries (600s TTL) would be deleted after 60s
            max_ttl = max(600, self.ttl_seconds)
            expired_keys = []
            for k, timestamp in self.notifications.items():
                if current_time - timestamp >= max_ttl:
                    expired_keys.append(k)
            
            for k in expired_keys:
                del self.notifications[k]
            
            # Check if notification is duplicate
            if key in self.notifications:
                last_time = self.notifications[key]
                time_since = current_time - last_time
                
                if time_since < ttl:
                    logger.debug(f"Notification deduplicated: {key} (sent {time_since:.1f}s ago, TTL={ttl}s)")
                    return False
            
            # Not a duplicate - record and allow
            self.notifications[key] = current_time
            logger.debug(f"Notification allowed: {key} (TTL={ttl}s)")
            return True
    
    def clear(self):
        """Clear all deduplication records"""
        with self.lock:
            self.notifications.clear()
            logger.info("Notification deduplicator cleared")


# Global deduplicator instance (2s for Camera 3, 600s for Camera 4-16)
deduplicator = NotificationDeduplicator(ttl_seconds=2)


def send_detection_alert(camera_id, object_class=None, direction=None, image_url=None, tracking_id=None):
    """
    Send detection alert to Zalo group
    
    Args:
        camera_id: Camera identifier
        object_class: Detected object class (person/car/motorbike/truck)
        direction: Direction for Cam 3 (IN/OUT) or None for Cam 4-17
        image_url: Google Drive image link
        tracking_id: Tracking ID for Cam 3 (used for deduplication)
    
    Returns:
        True if sent successfully, False otherwise
    """
    try:
        # Check if Zalo is enabled for this camera (default: True)
        try:
            import json
            from pathlib import Path
            config_path = Path(__file__).parent.parent / 'camera_class_configs.json'
            if config_path.exists():
                with open(config_path, 'r') as f:
                    camera_configs = json.load(f)
                cam_config = camera_configs.get(str(camera_id), {})
                zalo_enabled = cam_config.get('zalo_enabled', True)  # Default to True if not specified
                if not zalo_enabled:
                    logger.info(f"Camera {camera_id}: Zalo notifications disabled in config")
                    return False
        except Exception as e:
            logger.warning(f"Could not check zalo_enabled config: {e}, proceeding with notification")
        
        # Check deduplication for all cameras
        if not deduplicator.should_send(camera_id, tracking_id, direction):
            logger.info(f"Camera {camera_id}: Notification deduplicated")
            return False
        
        # Get Zalo configuration
        try:
            config = get_config()
            group_id = (config.get("ZALO_GROUP_ID") or "").strip()
            if not group_id:
                logger.error("Zalo config missing: ZALO_GROUP_ID not set")
                return False
        except Exception as e:
            logger.error(f"Failed to load Zalo config: {e}")
            return False
        
        # Get access token
        try:
            access_token = get_zalo_access_token()
        except FlowError as exc:
            logger.error(f"Failed to acquire Zalo access token: {exc}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error acquiring Zalo token: {e}")
            return False
        
        # Translation mapping
        translations = {
            "person": "người",
            "car": "xe hơi",
            "motorbike": "xe máy",
            "truck": "xe tải",
            "cow": "con bò",
            "IN": "VÀO",
            "OUT": "RA"
        }

        # Translate object class
        obj_cls = object_class or 'person'
        obj_cls_vn = translations.get(obj_cls.lower(), obj_cls)

        # Build message text
        if direction:
            # Camera 3 - include direction
            direction_vn = translations.get(direction, direction)
            message_text = f"Camera {camera_id} phát hiện {obj_cls_vn} {direction_vn}"
        else:
            # Camera 4-16 - simple message
            message_text = f"Camera {camera_id} phát hiện {obj_cls_vn}"
        
        # Add image URL to message
        if image_url:
            message_text += f"\n{image_url}"
        
        # Build payload
        payload = {
            "recipient": {"group_id": group_id},
            "message": {"text": message_text}
        }
        
        # Add image attachment if available
        if image_url and image_url.startswith(("http://", "https://")):
            payload["message"]["attachment"] = {
                "type": "template",
                "payload": {
                    "template_type": "media",
                    "elements": [
                        {"media_type": "image", "url": image_url}
                    ]
                }
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
            logger.info(f"Zalo notification sent: Camera {camera_id}, {object_class}, {direction}")
            return True
        else:
            try:
                err = resp.json()
                logger.error(f"Zalo API error: {err}")
            except:
                logger.error(f"Zalo API error: HTTP {resp.status_code}")
            return False
        
    except Exception as e:
        logger.error(f"Error sending Zalo notification: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return False


def clear_deduplicator():
    """Clear deduplication cache (for testing or manual reset)"""
    deduplicator.clear()


# Initialize on module import
logger.info("Zalo notification module loaded with deduplication")
