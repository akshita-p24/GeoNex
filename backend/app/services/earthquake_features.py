"""
Earthquake feature generation for GeoNex.

This module converts USGS earthquake results into a small,
ML-ready feature set.

These features are NOT yet passed into the existing Random Forest.
The current RF was not trained with earthquake features.
"""

from typing import Any


def generate_earthquake_features(
    earthquake_data: dict[str, Any],
) -> dict[str, float | int | None]:
    """
    Convert USGS earthquake results into standardized features.

    Expected input:
        Output returned by get_recent_earthquakes().
    """

    earthquakes = earthquake_data.get("earthquakes", [])

    if not earthquakes:
        return {
            "earthquake_present": 0,
            "earthquake_magnitude": None,
            "earthquake_distance_km": None,
            "earthquake_age_hours": None,
        }

    # Ignore malformed events.
    valid_events = [
        event
        for event in earthquakes
        if event.get("magnitude") is not None
        and event.get("distance_km") is not None
        and event.get("age_hours") is not None
    ]

    if not valid_events:
        return {
            "earthquake_present": 0,
            "earthquake_magnitude": None,
            "earthquake_distance_km": None,
            "earthquake_age_hours": None,
        }

    # Strongest earthquake.
    strongest = max(
        valid_events,
        key=lambda event: event["magnitude"],
    )

    # Nearest earthquake.
    nearest = min(
        valid_events,
        key=lambda event: event["distance_km"],
    )

    return {
        "earthquake_present": 1,
        "earthquake_magnitude": float(strongest["magnitude"]),
        "earthquake_distance_km": float(nearest["distance_km"]),
        "earthquake_age_hours": float(nearest["age_hours"]),
    }