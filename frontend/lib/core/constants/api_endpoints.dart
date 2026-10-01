/// api_endpoints.dart
///
/// Central endpoint definitions for GeoNex.
/// Architecture: Flutter Android App -> FastAPI Backend -> PostgreSQL + PostGIS on Supabase.
class ApiEndpoints {
  // Production / Staging base URLs (overridden at runtime by AuthService.baseUrl)
  static const String defaultBaseUrl = 'http://10.0.2.2:8000'; // Android emulator default
  static const String lanBaseUrl = 'http://10.235.29.64:8000'; // Physical device over LAN
  static const String mlBaseUrl = 'http://10.235.29.64:8000';

  // Core API paths (all prefixed with /api/v1 by backend)
  static const String authLogin = '/api/v1/auth/login';
  static const String authRegister = '/api/v1/auth/register';
  static const String authMe = '/api/v1/auth/me';

  static const String reports = '/api/v1/reports';
  static const String reportVerify = '/api/v1/reports/{id}/verify';
  static const String reportMedia = '/api/v1/reports/{id}/media';
  static const String reportsGeoJson = '/api/v1/reports/geojson';

  static const String riskLive = '/api/v1/risk/live';
  static const String riskLocation = '/api/v1/risk/location';
  static const String riskRoad = '/api/v1/risk/road';
  static const String riskArea = '/api/v1/risk/area';
  static const String routesRiskAware = '/api/v1/routes/risk-aware';
  static const String actionStatus = '/api/v1/actions/{id}/status';
  static const String alertsActive = '/api/v1/alerts/active';

  // Map & GIS Services (Google Maps Platform)
  static const String googleMapsApiKey = 'AIzaSyDTAfpb1gEwWXDShN0M8XU25FVZSiKGqmA';
}
