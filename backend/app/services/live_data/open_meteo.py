import asyncio
from datetime import datetime, timezone

import httpx


OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

# Example NER location.
# We will later make this configurable for different locations.
LATITUDE = 27.55
LONGITUDE = 93.65


async def fetch_open_meteo(latitude: float, longitude: float) -> dict:
    params = {
        "latitude": latitude,
        "longitude": longitude,
        "hourly": ",".join(
            [
                "rain",
                "soil_moisture_0_to_7cm",
            ]
        ),
        "past_days": 30,
        "forecast_days": 1,
        "timezone": "UTC",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(OPEN_METEO_URL, params=params)
        response.raise_for_status()
        return response.json()


def calculate_features(data: dict) -> dict:
    hourly = data["hourly"]

    times = hourly["time"]
    rainfall = hourly["rain"]
    soil_moisture = hourly["soil_moisture_0_to_7cm"]

    # Replace missing values with zero for rainfall.
    rainfall = [
        float(value) if value is not None else 0.0
        for value in rainfall
    ]

    soil_moisture = [
        float(value) if value is not None else None
        for value in soil_moisture
    ]

    # Remove missing soil-moisture observations.
    valid_soil = [value for value in soil_moisture if value is not None]

    def last_hours(total_hours: int) -> list[float]:
        return rainfall[-total_hours:]

    rain_1d_values = last_hours(24)
    rain_3d_values = last_hours(72)
    rain_7d_values = last_hours(168)
    rain_14d_values = last_hours(336)
    rain_30d_values = last_hours(720)

    rainfall_1d = sum(rain_1d_values)
    rainfall_3d = sum(rain_3d_values)
    rainfall_7d = sum(rain_7d_values)
    rainfall_14d = sum(rain_14d_values)
    rainfall_30d = sum(rain_30d_values)

    # Maximum rolling 24-hour rainfall inside the requested windows.
    def max_24h(window: list[float]) -> float:
        if len(window) < 24:
            return sum(window)

        return max(
            sum(window[i:i + 24])
            for i in range(len(window) - 23)
        )

    rainfall_max_3d = max_24h(rain_3d_values)
    rainfall_max_7d = max_24h(rain_7d_values)

    def rainy_days(window: list[float]) -> int:
        # A day counts as rainy when daily accumulated rainfall >= 1 mm.
        days = 0

        for i in range(0, len(window), 24):
            day = window[i:i + 24]

            if sum(day) >= 1.0:
                days += 1

        return days

    rainy_days_7d = rainy_days(rain_7d_values)
    rainy_days_14d = rainy_days(rain_14d_values)
    rainy_days_30d = rainy_days(rain_30d_values)

    current_soil_moisture = (
        valid_soil[-1] if valid_soil else None
    )

    soil_3d_values = [
        value for value in soil_moisture[-72:]
        if value is not None
    ]

    soil_7d_values = [
        value for value in soil_moisture[-168:]
        if value is not None
    ]

    soil_moisture_3d_mean = (
        sum(soil_3d_values) / len(soil_3d_values)
        if soil_3d_values
        else None
    )

    soil_moisture_7d_mean = (
        sum(soil_7d_values) / len(soil_7d_values)
        if soil_7d_values
        else None
    )

    # Approximate change between the current value and the
    # corresponding historical mean.
    soil_moisture_change_3d = (
        current_soil_moisture - soil_moisture_3d_mean
        if current_soil_moisture is not None
        and soil_moisture_3d_mean is not None
        else None
    )

    soil_moisture_change_7d = (
        current_soil_moisture - soil_moisture_7d_mean
        if current_soil_moisture is not None
        and soil_moisture_7d_mean is not None
        else None
    )

    return {
        "latitude": data["latitude"],
        "longitude": data["longitude"],
        "timezone": data["timezone"],
        "last_observation": times[-1],
        "fetched_at": datetime.now(timezone.utc).isoformat(),

        "rainfall_1d": rainfall_1d,
        "rainfall_3d": rainfall_3d,
        "rainfall_7d": rainfall_7d,
        "rainfall_14d": rainfall_14d,
        "rainfall_30d": rainfall_30d,
        "rainfall_max_3d": rainfall_max_3d,
        "rainfall_max_7d": rainfall_max_7d,

        "rainy_days_7d": rainy_days_7d,
        "rainy_days_14d": rainy_days_14d,
        "rainy_days_30d": rainy_days_30d,

        "soil_moisture": current_soil_moisture,
        "soil_moisture_3d_mean": soil_moisture_3d_mean,
        "soil_moisture_7d_mean": soil_moisture_7d_mean,
        "soil_moisture_change_3d": soil_moisture_change_3d,
        "soil_moisture_change_7d": soil_moisture_change_7d,
    }


async def main():
    print("Fetching live Open-Meteo data...")

    data = await fetch_open_meteo(
        LATITUDE,
        LONGITUDE,
    )

    features = calculate_features(data)

    print("\nLIVE DYNAMIC FEATURES")
    print("=" * 50)

    for key, value in features.items():
        print(f"{key}: {value}")


if __name__ == "__main__":
    asyncio.run(main())