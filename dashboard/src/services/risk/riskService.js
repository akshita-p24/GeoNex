import { RISK_ZONES_GEOJSON } from '../../data/geojson/riskZones.js';
import { apiFetch } from '../apiClient.js';
import { evaluateSpatialRisk } from './spatialRiskEvaluator.js';

export const riskService = {
  /**
   * Fetch spatial GeoJSON risk area grid from M3 backend.
   */
  async getRiskArea(
    minLat = 26.8,
    maxLat = 27.6,
    minLon = 93.1,
    maxLon = 94.0
  ) {
    try {
      const data = await apiFetch(
        `/risk/area?min_lat=${minLat}&max_lat=${maxLat}&min_lon=${minLon}&max_lon=${maxLon}`
      );

      if (data && data.features && data.features.length > 0) {
        return data;
      }

      return RISK_ZONES_GEOJSON;
    } catch {
      return RISK_ZONES_GEOJSON;
    }
  },

  /**
   * Fetch AI prediction for a coordinate point.
   *
   * Sends the complete feature set expected by the M1
   * Random Forest model through the M3 FastAPI backend.
   */
  async getRiskByLocation(lat, lon, rainfall24h = null, slope = null) {
    const spatialAssessment = evaluateSpatialRisk(lat, lon);

    const rain24h =
      rainfall24h !== null
        ? rainfall24h
        : spatialAssessment.rainfall_24h ?? 20;

    const slopeValue =
      slope !== null
        ? slope
        : spatialAssessment.slope_deg ?? 25;

    const params = new URLSearchParams({
      lat: String(lat),
      lon: String(lon),

      // Static M1 features
      elevation: String(spatialAssessment.elevation ?? 500),
      slope: String(slopeValue),
      curvature: String(spatialAssessment.curvature ?? 0),
      soil_type: String(spatialAssessment.soil_type ?? 1),
      ndvi_2017: String(spatialAssessment.ndvi_2017 ?? 0.5),
      distance_to_river_m: String(
        spatialAssessment.distance_to_river_m ?? 1000
      ),
      distance_to_road_m: String(
        spatialAssessment.distance_to_road_m ?? 1000
      ),
      distance_to_village_m: String(
        spatialAssessment.distance_to_village_m ?? 2000
      ),
      aspect_sin: String(spatialAssessment.aspect_sin ?? 0),
      aspect_cos: String(spatialAssessment.aspect_cos ?? 1),

      // Dynamic rainfall features
      rainfall_1d: String(rain24h),
      rainfall_3d: String(
        spatialAssessment.rainfall_3d ?? rain24h * 2
      ),
      rainfall_7d: String(
        spatialAssessment.rainfall_7d ?? rain24h * 3.5
      ),
      rainfall_14d: String(
        spatialAssessment.rainfall_14d ?? rain24h * 5
      ),
      rainfall_30d: String(
        spatialAssessment.rainfall_30d ?? rain24h * 7
      ),
      rainfall_max_3d: String(
        spatialAssessment.rainfall_max_3d ?? rain24h
      ),
      rainfall_max_7d: String(
        spatialAssessment.rainfall_max_7d ?? rain24h
      ),
      rainy_days_7d: String(
        spatialAssessment.rainy_days_7d ?? 3
      ),
      rainy_days_14d: String(
        spatialAssessment.rainy_days_14d ?? 5
      ),
      rainy_days_30d: String(
        spatialAssessment.rainy_days_30d ?? 10
      ),

      // Dynamic soil-moisture features
      soil_moisture: String(
        spatialAssessment.soil_moisture ?? 0.42
      ),
      soil_moisture_3d_mean: String(
        spatialAssessment.soil_moisture_3d_mean ?? 0.40
      ),
      soil_moisture_7d_mean: String(
        spatialAssessment.soil_moisture_7d_mean ?? 0.38
      ),
      soil_moisture_change_3d: String(
        spatialAssessment.soil_moisture_change_3d ?? 0.02
      ),
      soil_moisture_change_7d: String(
        spatialAssessment.soil_moisture_change_7d ?? 0.04
      ),
    });

    try {
      const liveData = await apiFetch(
        `/risk/location?${params.toString()}`
      );

      if (liveData) {
        const snapshot = liveData.feature_snapshot ?? {};

        return {
          ...spatialAssessment,
          ...liveData,

          risk_score:
            liveData.risk_score ??
            snapshot.dynamic_score ??
            spatialAssessment.risk_score,

          risk_level:
            liveData.risk_level ??
            snapshot.final_risk ??
            spatialAssessment.risk_level,

          confidence:
            liveData.confidence ??
            spatialAssessment.confidence ??
            0,

          rainfall_24h: rain24h,
          slope_deg: slopeValue,

          // Preserve model scores returned by M3
          static_score: snapshot.static_score ?? null,
          dynamic_score: snapshot.dynamic_score ?? null,
          static_class: snapshot.static_class ?? null,
          dynamic_class: snapshot.dynamic_class ?? null,
          final_risk: snapshot.final_risk ?? liveData.risk_level,
          model_version: liveData.model_version ?? null,
        };
      }

      return spatialAssessment;
    } catch (error) {
      console.warn(
        '[riskService] M3 risk prediction failed:',
        error
      );

      return spatialAssessment;
    }
  },

  /**
   * Directly evaluate local fallback risk for a tapped coordinate.
   */
  evaluatePointRisk(lat, lon) {
    return evaluateSpatialRisk(lat, lon);
  },
};