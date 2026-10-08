import os
import json
import logging
from typing import List, Dict, Any, Tuple, Optional
import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger("talentloq.firebase")

_firebase_initialized = False

def init_firebase() -> bool:
    """
    Initializes Firebase Admin SDK once from FIREBASE_CREDENTIALS environment variable.
    FIREBASE_CREDENTIALS can be:
      1. A path to a service account JSON file, or
      2. A raw JSON string containing the service account key.
    If not provided, operates in simulation mode (logs pushes without crashing).
    """
    global _firebase_initialized

    if firebase_admin._apps:
        _firebase_initialized = True
        return True

    cred_env = os.environ.get("FIREBASE_CREDENTIALS", "").strip()
    if not cred_env:
        logger.warning("[FCM] FIREBASE_CREDENTIALS not set; FCM running in simulation/mock mode.")
        _firebase_initialized = False
        return False

    try:
        if os.path.isfile(cred_env):
            cred = credentials.Certificate(cred_env)
        else:
            parsed = json.loads(cred_env)
            cred = credentials.Certificate(parsed)

        firebase_admin.initialize_app(cred)
        _firebase_initialized = True
        logger.info("[FCM] Firebase Admin SDK initialized successfully.")
        return True
    except Exception as e:
        logger.error(f"[FCM] Failed to initialize Firebase Admin SDK: {e}")
        _firebase_initialized = False
        return False


def is_firebase_initialized() -> bool:
    return bool(firebase_admin._apps)


def send_multicast_fcm(
    tokens: List[str],
    title: str,
    body: str,
    data: Optional[Dict[str, str]] = None,
) -> Tuple[int, List[str]]:
    """
    Dispatches push notification via FCM send_each_for_multicast.
    Returns:
      (success_count, dead_tokens_to_prune)
    Dead tokens include tokens with errorCode:
      - 'registration-token-not-registered'
      - 'invalid-argument'
    """
    if not tokens:
        return 0, []

    # Format data values strictly as strings per FCM requirement
    clean_data = {str(k): str(v) for k, v in (data or {}).items() if v is not None}

    if not is_firebase_initialized():
        logger.info(
            f"[FCM Simulation] Multicast to {len(tokens)} token(s) | Title: '{title}' | Body: '{body}' | Data: {clean_data}"
        )
        return len(tokens), []

    dead_tokens: List[str] = []
    success_count = 0

    try:
        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data=clean_data,
        )
        batch_response = messaging.send_each_for_multicast(message)
        success_count = batch_response.success_count

        for idx, resp in enumerate(batch_response.responses):
            if not resp.success:
                err_code = resp.exception.code if resp.exception and hasattr(resp.exception, "code") else ""
                err_str = str(resp.exception or "").lower()
                if (
                    err_code in ["registration-token-not-registered", "invalid-argument"]
                    or "not-registered" in err_str
                    or "invalid" in err_str
                ):
                    dead_tokens.append(tokens[idx])

        logger.info(
            f"[FCM] Batch of {len(tokens)} sent: {success_count} succeeded, {len(dead_tokens)} dead tokens pruned."
        )
    except Exception as e:
        logger.error(f"[FCM] Error dispatching multicast message: {e}")

    return success_count, dead_tokens
