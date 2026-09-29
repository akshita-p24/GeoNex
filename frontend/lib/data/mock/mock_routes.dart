import '../../core/constants/app_constants.dart';
import '../../core/models/route_model.dart';

class MockRoutesData {
  static List<RiskRoute> getRoutesForOriginDestination(
    String origin,
    String destination,
  ) {
    final cleanOrigin =
        origin.trim().isEmpty ? 'Selected Location' : origin.trim();

    final cleanDestination =
        destination.trim().isEmpty
            ? 'District Referral Hospital'
            : destination.trim();

    return [
      RiskRoute(
        routeId: 'route_a',
        name: 'ROUTE A (NH-415 Direct Arterial)',
        origin: cleanOrigin,
        destination: cleanDestination,
        distanceKm: 12.4,
        estimatedDurationMinutes: 22,
        riskLevel: RiskLevel.high,
        riskScore: 86.0,
        isRecommended: false,
        avoidanceReason:
            'HIGH RISK: Active tension cracks & debris overflow at Ch 14+200. High probability of complete blockage.',
        waypoints: const [
          RouteCoordinate(
            latitude: 27.1420,
            longitude: 93.6920,
            label: 'Start',
          ),
          RouteCoordinate(
            latitude: 27.1485,
            longitude: 93.6982,
            label: 'Hazard Zone (NH-415)',
          ),
          RouteCoordinate(
            latitude: 27.1550,
            longitude: 93.7050,
            label: 'Destination',
          ),
        ],
        hazardPointsOnRoute: const [
          'Tension Crack Ch 14+200',
          'Dikrong Culvert Mudflow',
        ],
      ),
      RiskRoute(
        routeId: 'route_b',
        name: 'ROUTE B (Valley Bypass via Nirjuli Ridge)',
        origin: cleanOrigin,
        destination: cleanDestination,
        distanceKm: 14.8,
        estimatedDurationMinutes: 29,
        riskLevel: RiskLevel.low,
        riskScore: 24.0,
        isRecommended: true,
        avoidanceReason:
            'LOW RISK (RECOMMENDED): Reinforced retaining wall corridor with active drainage channels. Safe for ambulances and civilian traffic.',
        waypoints: const [
          RouteCoordinate(
            latitude: 27.1420,
            longitude: 93.6920,
            label: 'Start',
          ),
          RouteCoordinate(
            latitude: 27.1390,
            longitude: 93.7120,
            label: 'Nirjuli Ridge',
          ),
          RouteCoordinate(
            latitude: 27.1510,
            longitude: 93.7190,
            label: 'East Valley Link',
          ),
          RouteCoordinate(
            latitude: 27.1550,
            longitude: 93.7050,
            label: 'Destination',
          ),
        ],
        hazardPointsOnRoute: const [],
      ),
      RiskRoute(
        routeId: 'route_c',
        name: 'ROUTE C (Upper Forest Ridge Link)',
        origin: cleanOrigin,
        destination: cleanDestination,
        distanceKm: 13.2,
        estimatedDurationMinutes: 26,
        riskLevel: RiskLevel.moderate,
        riskScore: 54.0,
        isRecommended: false,
        avoidanceReason:
            'MODERATE RISK: Narrow single-lane pavement, minor surface water logging.',
        waypoints: const [
          RouteCoordinate(
            latitude: 27.1420,
            longitude: 93.6920,
            label: 'Start',
          ),
          RouteCoordinate(
            latitude: 27.1460,
            longitude: 93.7080,
            label: 'Forest Gate',
          ),
          RouteCoordinate(
            latitude: 27.1550,
            longitude: 93.7050,
            label: 'Destination',
          ),
        ],
        hazardPointsOnRoute: const [
          'Minor Surface Seepage',
        ],
      ),
    ];
  }
}