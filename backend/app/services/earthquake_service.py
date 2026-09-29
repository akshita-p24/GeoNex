"""
USGS Earthquake Service

Fetches recent earthquake activity near a given latitude/longitude
from the USGS Earthquake Catalog API.
"""

from datetime import datetime, timezone
from math import radians, sin, cos, sqrt, atan2
from typing import Any

import httpx


USGS_API_URL = "https://earthquake.usgs.gov/fdsnws/event/1/query"


def _calculate_distance_km(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    """Calculate great-circle distance between two coordinates."""

    earth_radius_km = 6371.0

    lat1_rad = radians(lat1)
    lat2_rad = radians(lat2)

    delta_lat = radians(lat2 - lat1)
    delta_lon = radians(lon2 - lon1)

    a = (
        sin(delta_lat / 2) ** 2
        + cos(lat1_rad)
        * cos(lat2_rad)
        * sin(delta_lon / 2) ** 2
    )

    c = 2 * atan2(sqrt(a), sqrt(1 - a))

    return earth_radius_km * c


def _calculate_age_hours(event_time_ms: int) -> float:
    """Calculate earthquake age in hours."""

    event_time = datetime.fromtimestamp(
        event_time_ms / 1000,
        tz=timezone.utc,
    )

    now = datetime.now(timezone.utc)

    age_seconds = (now - event_time).total_seconds()

    return max(age_seconds / 3600.0, 0.0)


async def get_recent_earthquakes(
    latitude: float,
    longitude: float,
    radius_km: float = 200.0,
    hours: int = 72,
    min_magnitude: float = 2.5,
) -> dict[str, Any]:
    """
    Fetch recent earthquakes near a location.

    Parameters
    ----------
    latitude:
        Target latitude.

    longitude:
        Target longitude.

    radius_km:
        Search radius around the target location.

    hours:
        Look-back period in hours.

    min_magnitude:
        Minimum earthquake magnitude.

    Returns
    -------
    Dictionary containing earthquake events and summary information.
    """

    now = datetime.now(timezone.utc)

    start_time = now.timestamp() - (hours * 3600)

    start_datetime = datetime.fromtimestamp(
        start_time,
        tz=timezone.utc,
    )

    params = {
        "format": "geojson",
        "starttime": start_datetime.isoformat(),
        "endtime": now.isoformat(),
        "latitude": latitude,
        "longitude": longitude,
        "maxradiuskm": radius_km,
        "minmagnitude": min_magnitude,
        "orderby": "time",
        "limit": 100,
    }

    timeout = httpx.Timeout(15.0)

    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.get(
            USGS_API_URL,
            params=params,
        )

        response.raise_for_status()

        data = response.json()

    earthquakes = []

    for feature in data.get("features", []):
        properties = feature.get("properties", {})
        geometry = feature.get("geometry", {})

        coordinates = geometry.get("coordinates", [])

        if len(coordinates) < 3:
            continue

        event_longitude = coordinates[0]
        event_latitude = coordinates[1]
        event_depth_km = coordinates[2]

        magnitude = properties.get("mag")

        event_time_ms = properties.get("time")

        if event_time_ms is None:
            continue

        distance_km = _calculate_distance_km(
            latitude,
            longitude,
            event_latitude,
            event_longitude,
        )

        age_hours = _calculate_age_hours(event_time_ms)

        earthquakes.append(
            {
                "id": feature.get("id"),
                "magnitude": magnitude,
                "place": properties.get("place"),
                "latitude": event_latitude,
                "longitude": event_longitude,
                "depth_km": event_depth_km,
                "distance_km": round(distance_km, 2),
                "age_hours": round(age_hours, 2),
                "event_time": datetime.fromtimestamp(
                    event_time_ms / 1000,
                    tz=timezone.utc,
                ).isoformat(),
                "alert": properties.get("alert"),
                "tsunami": properties.get("tsunami"),
                "url": properties.get("url"),
            }
        )

    earthquakes.sort(
        key=lambda event: event["event_time"],
        reverse=True,
    )

    strongest = None

    if earthquakes:
        strongest = max(
            earthquakes,
            key=lambda event: (
                event["magnitude"]
                if event["magnitude"] is not None
                else -999
            ),
        )

    nearest = None

    if earthquakes:
        nearest = min(
            earthquakes,
            key=lambda event: event["distance_km"],
        )

    return {
        "source": "USGS Earthquake Catalog",
        "query": {
            "latitude": latitude,
            "longitude": longitude,
            "radius_km": radius_km,
            "hours": hours,
            "min_magnitude": min_magnitude,
        },
        "count": len(earthquakes),
        "earthquakes": earthquakes,
        "strongest": strongest,
        "nearest": nearest,
        "fetched_at": now.isoformat(),
    }