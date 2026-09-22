import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import '../core/constants/app_constants.dart';
import '../core/models/risk_data.dart';

import 'risk_engine.dart';
import 'mock_risk_engine.dart';

class FutureRiskApiEngine implements RiskEngine {
  final String apiEndpoint;
  final String? authToken;
  final MockRiskEngine _fallbackEngine = const MockRiskEngine();

  FutureRiskApiEngine({
    this.apiEndpoint = ApiEndpoints.mlBaseUrl,
    this.authToken,
  });

  @override
  Future<RiskResult> calculateRisk({
    required String locationId,
    required SusceptibilityFactors susceptibility,
    required DynamicConditions dynamicConditions,
  }) async {
    try {
      final uri = Uri.parse(
        '$apiEndpoint/api/v1/risk/location',
      ).replace(
        queryParameters: {
          'lat': '27.55',
          'lon': '93.65',

          'elevation': susceptibility.elevationMeters.toString(),
          'slope': susceptibility.slopeAngleDegrees.toString(),
          'curvature': '0.0',
          'soil_type': '1',
          'ndvi_2017': '0.5',
          'distance_to_river_m': '500.0',
          'distance_to_road_m': '1000.0',
          'distance_to_village_m': '2000.0',
          'aspect_sin': '0.0',
          'aspect_cos': '1.0',

          'rainfall_1d': dynamicConditions.rainfallMm.toString(),
          'rainfall_3d': dynamicConditions.rainfallMm.toString(),
          'rainfall_7d': dynamicConditions.rainfallMm.toString(),
          'rainfall_14d':
              dynamicConditions.rainfallForecastMm.toString(),
          'rainfall_30d':
              dynamicConditions.rainfallForecastMm.toString(),
          'rainfall_max_3d':
              dynamicConditions.rainfallMm.toString(),
          'rainfall_max_7d':
              dynamicConditions.rainfallMm.toString(),
          'rainy_days_7d': '1',
          'rainy_days_14d': '1',
          'rainy_days_30d': '1',

          'soil_moisture':
              dynamicConditions.soilMoistureIndex.toString(),
          'soil_moisture_3d_mean':
              dynamicConditions.soilMoistureIndex.toString(),
          'soil_moisture_7d_mean':
              dynamicConditions.soilMoistureIndex.toString(),
          'soil_moisture_change_3d': '0.0',
          'soil_moisture_change_7d': '0.0',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (authToken != null)
            'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Risk API returned ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final featureSnapshot =
          data['feature_snapshot'] as Map<String, dynamic>;

      final staticScore =
          (featureSnapshot['static_score'] as num).toDouble();

      final dynamicScore =
          (featureSnapshot['dynamic_score'] as num).toDouble();

      final finalRisk =
          featureSnapshot['final_risk']?.toString() ??
          data['risk_level']?.toString() ??
          'LOW';

      return RiskResult(
        locationId: locationId,
        riskScore: double.parse(
          (dynamicScore * 100).toStringAsFixed(1),
        ),
        riskLevel: _parseRiskLevel(finalRisk),
        confidence: 0.0,
        susceptibilityIndex: double.parse(
          (staticScore * 100).toStringAsFixed(1),
        ),
        dynamicTriggerIndex: double.parse(
          (dynamicScore * 100).toStringAsFixed(1),
        ),
        factorContributions: const {},
        timestamp: DateTime.now(),
      );
    } catch (e) {
      // Keep the application usable if the backend is unavailable.
      return _fallbackEngine.calculateRiskSync(
        locationId: locationId,
        susceptibility: susceptibility,
        dynamicConditions: dynamicConditions,
      );
    }
  }

  RiskLevel _parseRiskLevel(dynamic value) {
    switch (value.toString().toUpperCase()) {
      case 'CRITICAL':
        return RiskLevel.critical;
      case 'HIGH':
        return RiskLevel.high;
      case 'MODERATE':
        return RiskLevel.moderate;
      default:
        return RiskLevel.low;
    }
  }

  @override
  RiskResult calculateRiskSync({
    required String locationId,
    required SusceptibilityFactors susceptibility,
    required DynamicConditions dynamicConditions,
  }) {
    return _fallbackEngine.calculateRiskSync(
      locationId: locationId,
      susceptibility: susceptibility,
      dynamicConditions: dynamicConditions,
    );
  }

  @override
  Future<Map<String, RiskResult>> calculateBatchRisk(
    List<RiskLocation> locations,
  ) async {
    final Map<String, RiskResult> results = {};

    for (final location in locations) {
      results[location.id] = await calculateRisk(
        locationId: location.id,
        susceptibility: location.susceptibility,
        dynamicConditions: location.dynamicConditions,
      );
    }

    return results;
  }
}