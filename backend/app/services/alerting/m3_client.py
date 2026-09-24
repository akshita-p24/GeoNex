import json
import logging
from typing import Any, Dict, List

import httpx

from app.core.config import get_settings
from app.core.exceptions import ExternalServiceError

settings = get_settings()
logger = logging.getLogger(__name__)

_SERVICE_KEY_HEADER = "X-Internal-Service-Key"

_client: "httpx.AsyncClient | None" = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(base_url=settings.M3_BASE_URL, timeout=settings.M3_HTTP_TIMEOUT_SECONDS)
    return _client


async def resolve_recipients(area_id: str, alert_id: str, severity: str) -> List[Dict[str, Any]]:
    """Resolve notification recipients for a given alert via M3's
    geo-targeting API (architecture §29). M5 never performs its own
    spatial calculations and never queries the user table directly.

    Response shape per §29:
    ``[{"recipient_id", "phone_number"?, "device_token"?,
        "preferred_channels": [...], "priority", "preferred_locale"?}, ...]``
    """
    client = _get_client()
    headers = {_SERVICE_KEY_HEADER: settings.M5_SERVICE_KEY or settings.M3_SERVICE_KEY, "Content-Type": "application/json"}
    payload = {"area_id": area_id, "alert_id": alert_id, "severity": severity}
    try:
        response = await client.post("/recipients/resolve", headers=headers, content=json.dumps(payload))
        response.raise_for_status()
    except httpx.HTTPError as exc:
        raise ExternalServiceError(f"M3 recipient resolution failed: {exc}") from exc
    return response.json()


async def close_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
