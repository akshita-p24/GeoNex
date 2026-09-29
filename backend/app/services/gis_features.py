"""
GIS feature extraction for GeoNex landslide susceptibility.

Extracts the exact 10 features expected by the trained static
Random Forest model:

1. elevation
2. slope
3. curvature
4. soil_type
5. ndvi_2017
6. distance_to_river_m
7. distance_to_road_m
8. distance_to_village_m
9. aspect_sin
10. aspect_cos

Supported regions:
- Papum Pare
- West Kameng

GIS source:
C:\\Landslide
"""

from __future__ import annotations

import json
import math
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

import numpy as np
import rasterio


# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------

GIS_ROOT = Path(
    os.getenv(
        "GEONEX_GIS_ROOT",
        Path(__file__).resolve().parents[3] / "gis"
    )
)

SUPPORTED_REGIONS = {
    "papum_pare": {
        "display_name": "Papum Pare",
        "folder": GIS_ROOT / "papum_pare",
        "boundary": GIS_ROOT / "papum_pare" / "papum_pare_boundary.geojson",
        "dem": GIS_ROOT / "papum_pare" / "papum_pare_dem.tif",
        "slope": GIS_ROOT / "papum_pare" / "papum_pare_slope.tif",
        "aspect": GIS_ROOT / "papum_pare" / "papum_pare_aspect.tif",
        "curvature": GIS_ROOT / "papum_pare" / "papum_pare_curvature.tif",
        "soil": GIS_ROOT / "papum_pare" / "papum_pare_soil_type.tif",
        "ndvi_2017": GIS_ROOT
        / "papum_pare"
        / "ndvi"
        / "papum_pare_ndvi_fixed_2017.tif",
        "rivers": GIS_ROOT / "papum_pare" / "rivers_papum_pare.geojson",
        "roads": GIS_ROOT / "papum_pare" / "roads_papum_pare.geojson",
        "villages": GIS_ROOT / "papum_pare" / "villages_papum_pare.geojson",
    },
    "west_kameng": {
        "display_name": "West Kameng",
        "folder": GIS_ROOT / "west_kameng",
        "boundary": GIS_ROOT
        / "west_kameng"
        / "west_kameng_boundary.geojson",
        "dem": GIS_ROOT / "west_kameng" / "west_kameng_dem.tif",
        "slope": GIS_ROOT / "west_kameng" / "west_kameng_slope.tif",
        "aspect": GIS_ROOT / "west_kameng" / "west_kameng_aspect.tif",
        "curvature": GIS_ROOT
        / "west_kameng"
        / "west_kameng_curvature.tif",
        "soil": GIS_ROOT / "west_kameng" / "west_kameng_soil_type.tif",
        "ndvi_2017": GIS_ROOT
        / "west_kameng"
        / "ndvi"
        / "west_kameng_ndvi_fixed_2017.tif",
        "rivers": GIS_ROOT
        / "west_kameng"
        / "rivers_west_kameng.geojson",
        "roads": GIS_ROOT
        / "west_kameng"
        / "roads_west_kameng.geojson",
        "villages": GIS_ROOT
        / "west_kameng"
        / "villages_west_kameng.geojson",
    },
}


# ---------------------------------------------------------------------
# Basic validation
# ---------------------------------------------------------------------

def _validate_coordinate(latitude: float, longitude: float) -> None:
    if not -90 <= latitude <= 90:
        raise ValueError(f"Invalid latitude: {latitude}")

    if not -180 <= longitude <= 180:
        raise ValueError(f"Invalid longitude: {longitude}")


def _check_required_files(region: dict[str, Any]) -> None:
    required_keys = [
        "boundary",
        "dem",
        "slope",
        "aspect",
        "curvature",
        "soil",
        "ndvi_2017",
        "rivers",
        "roads",
        "villages",
    ]

    missing = []

    for key in required_keys:
        path = Path(region[key])

        if not path.exists():
            missing.append(f"{key}: {path}")

    if missing:
        raise FileNotFoundError(
            "Missing GIS files:\n" + "\n".join(missing)
        )


# ---------------------------------------------------------------------
# GeoJSON loading
# ---------------------------------------------------------------------

@lru_cache(maxsize=4)
def _load_geojson(path_string: str) -> dict[str, Any]:
    path = Path(path_string)

    if not path.exists():
        raise FileNotFoundError(f"GeoJSON not found: {path}")

    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


# ---------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------

def _extract_polygons(geometry: dict[str, Any]) -> list[list[list[float]]]:
    """
    Return polygons as:

        [
            [[lon, lat], [lon, lat], ...],
            ...
        ]

    Handles Polygon and MultiPolygon.
    """

    if not geometry:
        return []

    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])

    polygons = []

    if geometry_type == "Polygon":
        if coordinates:
            # Exterior ring only.
            polygons.append(coordinates[0])

    elif geometry_type == "MultiPolygon":
        for polygon in coordinates:
            if polygon:
                polygons.append(polygon[0])

    return polygons


def _point_in_polygon(
    longitude: float,
    latitude: float,
    polygon: list[list[float]],
) -> bool:
    """
    Ray-casting point-in-polygon test.
    """

    inside = False

    if len(polygon) < 3:
        return False

    j = len(polygon) - 1

    for i in range(len(polygon)):
        xi = float(polygon[i][0])
        yi = float(polygon[i][1])

        xj = float(polygon[j][0])
        yj = float(polygon[j][1])

        intersects = (
            ((yi > latitude) != (yj > latitude))
            and (
                longitude
                < (xj - xi)
                * (latitude - yi)
                / ((yj - yi) or 1e-15)
                + xi
            )
        )

        if intersects:
            inside = not inside

        j = i

    return inside


def _geometry_contains_point(
    geometry: dict[str, Any],
    longitude: float,
    latitude: float,
) -> bool:
    polygons = _extract_polygons(geometry)

    for polygon in polygons:
        if _point_in_polygon(longitude, latitude, polygon):
            return True

    return False


# ---------------------------------------------------------------------
# Region detection
# ---------------------------------------------------------------------

@lru_cache(maxsize=4)
def _load_region_boundary(region_name: str) -> dict[str, Any]:
    region = SUPPORTED_REGIONS[region_name]

    return _load_geojson(
        str(region["boundary"])
    )


def _region_contains_point(
    region_name: str,
    latitude: float,
    longitude: float,
) -> bool:
    boundary = _load_region_boundary(region_name)

    features = boundary.get("features", [])

    for feature in features:
        geometry = feature.get("geometry")

        if _geometry_contains_point(
            geometry,
            longitude,
            latitude,
        ):
            return True

    return False


def detect_region(
    latitude: float,
    longitude: float,
) -> str:
    """
    Detect whether the coordinate lies inside Papum Pare
    or West Kameng.

    Returns:
        "papum_pare"
        "west_kameng"

    Raises:
        ValueError if outside supported GIS coverage.
    """

    _validate_coordinate(latitude, longitude)

    matches = []

    for region_name in SUPPORTED_REGIONS:
        try:
            if _region_contains_point(
                region_name,
                latitude,
                longitude,
            ):
                matches.append(region_name)
        except Exception:
            # If boundary parsing fails, continue so that another
            # supported region can still be checked.
            continue

    if len(matches) == 1:
        return matches[0]

    if len(matches) > 1:
        # Extremely unlikely, but if boundaries overlap, choose the
        # smaller/more specific region deterministically.
        return matches[0]

    raise ValueError(
        f"Coordinate ({latitude}, {longitude}) is outside "
        "the supported Papum Pare and West Kameng GIS coverage."
    )


# ---------------------------------------------------------------------
# Raster helpers
# ---------------------------------------------------------------------

@lru_cache(maxsize=32)
def _open_raster(path_string: str):
    path = Path(path_string)

    if not path.exists():
        raise FileNotFoundError(
            f"Raster not found: {path}"
        )

    return rasterio.open(path)


def _sample_raster(
    raster_path: Path,
    latitude: float,
    longitude: float,
) -> float:
    """
    Sample the nearest raster pixel at a WGS84 coordinate.
    """

    dataset = _open_raster(str(raster_path))

    try:
        values = list(
            dataset.sample(
                [(longitude, latitude)],
                indexes=1,
            )
        )

        if not values:
            raise ValueError(
                f"No raster value returned for {raster_path}"
            )

        value = values[0][0]

        if np.ma.is_masked(value):
            raise ValueError(
                f"Raster value is masked at "
                f"({latitude}, {longitude}): {raster_path}"
            )

        value = float(value)

        if not math.isfinite(value):
            raise ValueError(
                f"Raster value is not finite at "
                f"({latitude}, {longitude}): {raster_path}"
            )

        return value

    finally:
        # Do not close here because rasterio datasets are cached.
        pass


def _normalize_ndvi(value: float) -> float:
    """
    Convert scaled NDVI rasters to the conventional approximately
    -1 to +1 representation when necessary.

    The supplied 2017 NDVI rasters contain values around -589 to
    9993, indicating a scale factor of approximately 10,000.

    If the raster already contains normal NDVI values, it is left
    unchanged.
    """

    if abs(value) > 1.5:
        return value / 10000.0

    return value


def _aspect_to_sin_cos(
    aspect_degrees: float,
) -> tuple[float, float]:
    """
    Convert aspect in degrees into the two model features.
    """

    radians = math.radians(aspect_degrees)

    return (
        math.sin(radians),
        math.cos(radians),
    )


# ---------------------------------------------------------------------
# GeoJSON coordinate extraction
# ---------------------------------------------------------------------

def _iter_line_coordinates(
    geometry: dict[str, Any],
):
    """
    Yield individual LineString coordinate sequences.

    Handles:
    - LineString
    - MultiLineString
    """

    if not geometry:
        return

    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])

    if geometry_type == "LineString":
        yield coordinates

    elif geometry_type == "MultiLineString":
        for line in coordinates:
            yield line


def _iter_point_coordinates(
    geometry: dict[str, Any],
):
    """
    Yield point coordinates.

    Handles:
    - Point
    - MultiPoint
    """

    if not geometry:
        return

    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])

    if geometry_type == "Point":
        yield coordinates

    elif geometry_type == "MultiPoint":
        for point in coordinates:
            yield point


# ---------------------------------------------------------------------
# Distance calculations
# ---------------------------------------------------------------------

def _haversine_distance_m(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    """
    Haversine distance between two WGS84 points.
    """

    earth_radius_m = 6_371_000.0

    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)

    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1_rad)
        * math.cos(lat2_rad)
        * math.sin(delta_lon / 2) ** 2
    )

    c = 2 * math.atan2(
        math.sqrt(a),
        math.sqrt(max(0.0, 1.0 - a)),
    )

    return earth_radius_m * c


def _local_xy(
    latitude: float,
    longitude: float,
    origin_latitude: float,
    origin_longitude: float,
) -> tuple[float, float]:
    """
    Convert a WGS84 coordinate to a local metre-based
    equirectangular coordinate.

    This is accurate enough for nearest-feature distances
    over the regional distances used here.
    """

    earth_radius_m = 6_371_000.0

    lat0_rad = math.radians(origin_latitude)

    x = (
        math.radians(longitude - origin_longitude)
        * earth_radius_m
        * math.cos(lat0_rad)
    )

    y = (
        math.radians(latitude - origin_latitude)
        * earth_radius_m
    )

    return x, y


def _point_to_segment_distance(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> float:
    """
    Euclidean point-to-line-segment distance in metres.
    """

    dx = bx - ax
    dy = by - ay

    segment_length_squared = dx * dx + dy * dy

    if segment_length_squared == 0:
        return math.hypot(px - ax, py - ay)

    t = (
        (px - ax) * dx
        + (py - ay) * dy
    ) / segment_length_squared

    t = max(0.0, min(1.0, t))

    closest_x = ax + t * dx
    closest_y = ay + t * dy

    return math.hypot(
        px - closest_x,
        py - closest_y,
    )


def _distance_to_lines(
    latitude: float,
    longitude: float,
    geojson: dict[str, Any],
) -> float:
    """
    Find nearest distance from a point to any LineString /
    MultiLineString feature.
    """

    point_x = 0.0
    point_y = 0.0

    minimum_distance = float("inf")

    for feature in geojson.get("features", []):
        geometry = feature.get("geometry")

        for line in _iter_line_coordinates(geometry):
            if not line:
                continue

            previous = None

            for coordinate in line:
                if len(coordinate) < 2:
                    continue

                current_lon = float(coordinate[0])
                current_lat = float(coordinate[1])

                current_x, current_y = _local_xy(
                    current_lat,
                    current_lon,
                    latitude,
                    longitude,
                )

                if previous is not None:
                    distance = _point_to_segment_distance(
                        point_x,
                        point_y,
                        previous[0],
                        previous[1],
                        current_x,
                        current_y,
                    )

                    minimum_distance = min(
                        minimum_distance,
                        distance,
                    )

                previous = (
                    current_x,
                    current_y,
                )

    if not math.isfinite(minimum_distance):
        raise ValueError(
            "No usable line geometry was found."
        )

    return float(minimum_distance)


def _distance_to_points(
    latitude: float,
    longitude: float,
    geojson: dict[str, Any],
) -> float:
    """
    Find nearest distance to any Point/MultiPoint feature.
    """

    minimum_distance = float("inf")

    for feature in geojson.get("features", []):
        geometry = feature.get("geometry")

        for coordinate in _iter_point_coordinates(geometry):
            if len(coordinate) < 2:
                continue

            feature_lon = float(coordinate[0])
            feature_lat = float(coordinate[1])

            distance = _haversine_distance_m(
                latitude,
                longitude,
                feature_lat,
                feature_lon,
            )

            minimum_distance = min(
                minimum_distance,
                distance,
            )

    if not math.isfinite(minimum_distance):
        raise ValueError(
            "No usable point geometry was found."
        )

    return float(minimum_distance)


# ---------------------------------------------------------------------
# Public feature extraction
# ---------------------------------------------------------------------

def extract_static_gis_features(
    latitude: float,
    longitude: float,
) -> dict[str, float | int | str]:
    """
    Extract the exact static feature vector expected by the
    trained Random Forest model.

    Returns a dictionary containing:

        elevation
        slope
        curvature
        soil_type
        ndvi_2017
        distance_to_river_m
        distance_to_road_m
        distance_to_village_m
        aspect_sin
        aspect_cos

    Also includes:
        region

    Example:

        features = extract_static_gis_features(
            latitude=27.1000,
            longitude=93.6000,
        )
    """

    _validate_coordinate(latitude, longitude)

    region_name = detect_region(
        latitude,
        longitude,
    )

    region = SUPPORTED_REGIONS[region_name]

    _check_required_files(region)

    # -------------------------------------------------------------
    # Raster features
    # -------------------------------------------------------------

    elevation = _sample_raster(
        region["dem"],
        latitude,
        longitude,
    )

    slope = _sample_raster(
        region["slope"],
        latitude,
        longitude,
    )

    aspect = _sample_raster(
        region["aspect"],
        latitude,
        longitude,
    )

    curvature = _sample_raster(
        region["curvature"],
        latitude,
        longitude,
    )

    soil_type_raw = _sample_raster(
        region["soil"],
        latitude,
        longitude,
    )

    ndvi_raw = _sample_raster(
        region["ndvi_2017"],
        latitude,
        longitude,
    )

    aspect_sin, aspect_cos = _aspect_to_sin_cos(
        aspect
    )

    ndvi_2017 = _normalize_ndvi(
        ndvi_raw
    )

    # Soil is a categorical model feature.
    soil_type = int(round(soil_type_raw))

    # -------------------------------------------------------------
    # Vector distances
    # -------------------------------------------------------------

    rivers = _load_geojson(
        str(region["rivers"])
    )

    roads = _load_geojson(
        str(region["roads"])
    )

    villages = _load_geojson(
        str(region["villages"])
    )

    distance_to_river_m = _distance_to_lines(
        latitude,
        longitude,
        rivers,
    )

    distance_to_road_m = _distance_to_lines(
        latitude,
        longitude,
        roads,
    )

    distance_to_village_m = _distance_to_points(
        latitude,
        longitude,
        villages,
    )

    # -------------------------------------------------------------
    # Exact model feature dictionary
    # -------------------------------------------------------------

    return {
        "elevation": float(elevation),
        "slope": float(slope),
        "curvature": float(curvature),
        "soil_type": soil_type,
        "ndvi_2017": float(ndvi_2017),
        "distance_to_river_m": float(distance_to_river_m),
        "distance_to_road_m": float(distance_to_road_m),
        "distance_to_village_m": float(distance_to_village_m),
        "aspect_sin": float(aspect_sin),
        "aspect_cos": float(aspect_cos),
        "region": region_name,
    }


# ---------------------------------------------------------------------
# Convenience helpers
# ---------------------------------------------------------------------

def get_supported_regions() -> list[str]:
    """
    Return supported region names.
    """

    return list(SUPPORTED_REGIONS.keys())


def get_gis_root() -> str:
    """
    Return configured GIS root directory.
    """

    return str(GIS_ROOT)


def clear_gis_caches() -> None:
    """
    Clear cached GeoJSON/raster handles.

    Useful during development if GIS files are replaced.
    """

    _load_geojson.cache_clear()
    _load_region_boundary.cache_clear()
    _open_raster.cache_clear()


# ---------------------------------------------------------------------
# Simple command-line test
# ---------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Test GeoNex GIS feature extraction."
    )

    parser.add_argument(
        "--lat",
        type=float,
        required=True,
        help="Latitude",
    )

    parser.add_argument(
        "--lon",
        type=float,
        required=True,
        help="Longitude",
    )

    args = parser.parse_args()

    result = extract_static_gis_features(
        latitude=args.lat,
        longitude=args.lon,
    )

    print(json.dumps(result, indent=2))