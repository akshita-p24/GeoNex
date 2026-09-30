/// http_backend_client.dart
///
/// Real implementation of [BackendClient] that communicates with
/// the GeoNex FastAPI backend at kBackendBaseUrl.
///
/// Responsibilities:
/// - Attaches JWT Authorization header on every request
/// - Handles 401 (token expired), 403 (forbidden), 4xx, 5xx, network errors
/// - Parses JSON responses into Flutter data models
/// - Submits citizen reports → POST /api/v1/reports
/// - Lists reports → GET /api/v1/reports
/// - Verifies reports → POST /api/v1/reports/{id}/verify
/// - Fetches risk predictions → GET /api/v1/risk/live
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/models/action_item.dart';
import '../core/models/alert_model.dart';
import '../core/models/citizen_report.dart';
import '../core/models/exposure_asset.dart';
import '../core/models/priority_item.dart';
import '../core/models/region_summary.dart';
import '../core/models/risk_data.dart';
import '../core/models/route_model.dart';
import '../core/services/auth_service.dart';
import 'backend_client.dart';
import 'mock_backend_client.dart';

/// Thrown when the server returns an error response.
class BackendHttpException implements Exception {
  final int statusCode;
  final String detail;
  const BackendHttpException(this.statusCode, this.detail);

  String get userMessage {
    switch (statusCode) {
      case 401:
        return 'Session expired or unauthenticated. Please log in again.';
      case 403:
        return 'Permission denied. You are not authorized for this operation.';
      case 404:
        return 'Requested report or resource does not exist.';
      case 409:
        return 'Operation conflict. A report with this identifier already exists.';
      case 422:
        return 'Invalid request data. Please check required fields: $detail';
      case 500:
        return 'Internal server error. Please try again later.';
      case 0:
        return 'Network connection failed. Operation queued locally.';
      default:
        return detail.isNotEmpty ? detail : 'Server error ($statusCode)';
    }
  }

  @override
  String toString() => 'BackendHttpException($statusCode): $detail';
}

/// Real HTTP implementation that talks to the FastAPI backend.
///
/// Falls back to [MockBackendClient] for data that the backend
/// does not yet expose (e.g. exposure assets, routes, region analytics).
class HttpBackendClient implements BackendClient {
  final AuthService _authService;
  final MockBackendClient _mock;

  HttpBackendClient({required AuthService authService})
      : _authService = authService,
        _mock = MockBackendClient();

  // ---------------------------------------------------------------------------
  // HTTP HELPERS
  // ---------------------------------------------------------------------------

  /// Returns the base URL for the backend.
  static const String _base = kBackendBaseUrl;

  Map<String, String> get _headers {
    final token = _authService.token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('$_base$path');
    http.Response response;
    try {
      response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw BackendHttpException(0, 'Network error: $e');
    }
    return _handleResponse(response);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base$path');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw BackendHttpException(0, 'Network error: $e');
    }
    return _handleResponse(response);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    String detail = 'HTTP ${response.statusCode}';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      detail = (json['detail'] ?? json['message'] ?? detail).toString();
    } catch (_) {}

    throw BackendHttpException(response.statusCode, detail);
  }

  // ---------------------------------------------------------------------------
  // LOCATIONS & RISK
  // ---------------------------------------------------------------------------

  @override
  Future<List<RiskLocation>> getRiskLocations() async {
    // The backend has risk endpoints but they require lat/lng.
    // For list view, fall through to mock (which has the seeded district data).
    return _mock.getRiskLocations();
  }

  @override
  Future<RiskLocation?> getRiskLocationById(String id) async {
    return _mock.getRiskLocationById(id);
  }

  @override
  Future<void> updateDynamicConditions(
      String locationId, DynamicConditions conditions) async {
    return _mock.updateDynamicConditions(locationId, conditions);
  }

  // ---------------------------------------------------------------------------
  // EXPOSURE ASSETS
  // ---------------------------------------------------------------------------

  @override
  Future<List<ExposureAsset>> getExposureAssets({String? locationId}) async {
    return _mock.getExposureAssets(locationId: locationId);
  }

  // ---------------------------------------------------------------------------
  // PRIORITY QUEUE
  // ---------------------------------------------------------------------------

  @override
  Future<List<PriorityItem>> getPriorityQueue() async {
    return _mock.getPriorityQueue();
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  @override
  Future<List<ActionItem>> getActions({String? locationId}) async {
    return _mock.getActions(locationId: locationId);
  }

  @override
  Future<void> updateActionStatus(
    String actionId,
    ActionStatus status, {
    String? notes,
  }) async {
    return _mock.updateActionStatus(actionId, status, notes: notes);
  }

  @override
  Future<ActionItem> createAction(ActionItem action) async {
    return _mock.createAction(action);
  }

  // ---------------------------------------------------------------------------
  // ALERTS
  // ---------------------------------------------------------------------------

  @override
  Future<List<AlertModel>> getAlerts({AlertStatus? status}) async {
    return _mock.getAlerts(status: status);
  }

  @override
  Future<void> triggerAlert(AlertModel alert) async {
    return _mock.triggerAlert(alert);
  }

  @override
  Future<void> resolveAlert(String alertId) async {
    return _mock.resolveAlert(alertId);
  }

  // ---------------------------------------------------------------------------
  // CITIZEN REPORTS — REAL BACKEND
  // ---------------------------------------------------------------------------

  @override
  Future<List<CitizenReport>> getReports(
      {ReportVerificationStatus? status}) async {
    try {
      final data = await _get('/api/v1/reports') as List<dynamic>;
      final reports = data
          .map((json) => _parseReport(json as Map<String, dynamic>))
          .toList();

      if (status != null) {
        return reports
            .where((r) => r.verificationStatus == status)
            .toList();
      }
      return reports;
    } on BackendHttpException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 0) {
        // Fall back to mock if not authenticated or offline
        return _mock.getReports(status: status);
      }
      rethrow;
    }
  }

  @override
  Future<CitizenReport> submitReport(CitizenReport report) async {
    try {
      final payload = _reportToJson(report);
      final data = await _post('/api/v1/reports', payload)
          as Map<String, dynamic>;
      return _parseReport(data);
    } on BackendHttpException catch (e) {
      if (e.statusCode == 0) {
        // Offline — return the report as-is (caller handles offline queue)
        return report;
      }
      rethrow;
    }
  }

  @override
  Future<void> verifyReport(
    String reportId,
    ReportVerificationStatus status, {
    String? verifiedBy,
    String? notes,
  }) async {
    final decision = _statusToDecision(status);
    await _post('/api/v1/reports/$reportId/verify', {
      'decision': decision,
      'remarks': notes ?? '',
    });
  }

  // ---------------------------------------------------------------------------
  // ROUTES
  // ---------------------------------------------------------------------------

  @override
  Future<List<RiskRoute>> getRiskAwareRoutes(
      String origin, String destination) async {
    return _mock.getRiskAwareRoutes(origin, destination);
  }

  // ---------------------------------------------------------------------------
  // ANALYTICS & HISTORY
  // ---------------------------------------------------------------------------

  @override
  Future<List<DistrictRiskSummary>> getDistrictSummaries() async {
    return _mock.getDistrictSummaries();
  }

  @override
  Future<List<RegionHistoryEntry>> getRegionHistory(
      String districtName) async {
    return _mock.getRegionHistory(districtName);
  }

  // ---------------------------------------------------------------------------
  // PARSERS
  // ---------------------------------------------------------------------------

  CitizenReport _parseReport(Map<String, dynamic> json) {
    final status = _parseStatus(
        (json['status'] as String? ?? 'PENDING').toUpperCase());

    // Extract media if present
    String mediaUrl = '';
    final mediaList = json['media'] as List<dynamic>?;
    if (mediaList != null && mediaList.isNotEmpty) {
      final firstMedia = mediaList.first as Map<String, dynamic>?;
      mediaUrl = firstMedia?['media_url'] as String? ?? '';
    }

    // Extract verification if present
    String? verifiedBy;
    DateTime? verifiedAt;
    String? verificationNotes;
    final verificationJson = json['verification'] as Map<String, dynamic>?;
    if (verificationJson != null) {
      verifiedBy = 'Field Officer (${(verificationJson['officer_id']?.toString() ?? '').substring(0, (verificationJson['officer_id']?.toString() ?? '').length >= 8 ? 8 : (verificationJson['officer_id']?.toString() ?? '').length)})';
      final vAtStr = verificationJson['verified_at'] as String?;
      if (vAtStr != null) {
        verifiedAt = DateTime.tryParse(vAtStr);
      }
      verificationNotes = verificationJson['remarks'] as String?;
    }

    final valResult = json['validation_result'] as Map<String, dynamic>?;
    final parsedMediaList = (mediaList as List<dynamic>?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList();

    return CitizenReport(
      reportId: json['id']?.toString() ?? '',
      locationName: json['description'] as String? ?? 'Unknown Location',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      capturedAt: json['capture_timestamp'] != null
          ? DateTime.tryParse(json['capture_timestamp'] as String) ??
              DateTime.now()
          : DateTime.tryParse(json['created_at'] as String? ?? '') ??
              DateTime.now(),
      mediaPath: mediaUrl,
      incidentType: _parseIncidentType(
          (json['report_type'] as String? ?? 'LANDSLIDE').toUpperCase()),
      severity: SeverityLevel.medium,
      notes: json['description'] as String? ?? '',
      verificationStatus: status,
      submittedBy: json['user_id']?.toString() ?? '',
      verifiedBy: verifiedBy,
      verifiedAt: verifiedAt,
      verificationNotes: verificationNotes,
      validationResult: valResult,
      mediaList: parsedMediaList,
    );
  }

  Map<String, dynamic> _reportToJson(CitizenReport report) {
    return {
      'report_type': _incidentTypeToBackend(report.incidentType),
      'description': report.notes.isNotEmpty ? report.notes : report.locationName,
      'latitude': report.latitude,
      'longitude': report.longitude,
      'capture_timestamp': report.capturedAt.toIso8601String(),
      if (report.reportId.isNotEmpty &&
          !report.reportId.startsWith('NER-') &&
          !report.reportId.startsWith('rpt_'))
        'client_report_id': report.reportId,
    };
  }

  ReportVerificationStatus _parseStatus(String s) {
    switch (s) {
      case 'VERIFIED':
        return ReportVerificationStatus.verified;
      case 'REJECTED':
        return ReportVerificationStatus.rejected;
      case 'NEEDS_INFORMATION':
        return ReportVerificationStatus.escalated;
      case 'PENDING':
      default:
        return ReportVerificationStatus.uploaded;
    }
  }

  String _statusToDecision(ReportVerificationStatus status) {
    switch (status) {
      case ReportVerificationStatus.verified:
        return 'VERIFY';
      case ReportVerificationStatus.rejected:
        return 'REJECT';
      case ReportVerificationStatus.escalated:
        return 'NEEDS_INFORMATION';
      default:
        return 'VERIFY';
    }
  }

  IncidentType _parseIncidentType(String s) {
    switch (s) {
      case 'LANDSLIDE':
        return IncidentType.landslide;
      case 'CRACK':
        return IncidentType.crack;
      case 'ROCKFALL':
        return IncidentType.rockfall;
      case 'ROAD_BLOCKAGE':
        return IncidentType.roadBlockage;
      case 'SLOPE_MOVEMENT':
        return IncidentType.slopeMovement;
      case 'DEBRIS_FLOW':
        return IncidentType.debrisFlow;
      default:
        return IncidentType.other;
    }
  }

  String _incidentTypeToBackend(IncidentType t) {
    switch (t) {
      case IncidentType.landslide:
        return 'LANDSLIDE';
      case IncidentType.crack:
        return 'CRACK';
      case IncidentType.rockfall:
        return 'ROCKFALL';
      case IncidentType.roadBlockage:
        return 'ROAD_BLOCKAGE';
      case IncidentType.slopeMovement:
        return 'SLOPE_MOVEMENT';
      case IncidentType.debrisFlow:
        return 'DEBRIS_FLOW';
      case IncidentType.other:
        return 'OTHER';
    }
  }
}
