import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/future_risk_api_engine.dart';
import '../ai/risk_engine.dart';
import '../backend/backend_client.dart';
import '../backend/mock_backend_client.dart';
import '../core/constants/app_constants.dart';
import '../core/models/action_item.dart';
import '../core/models/alert_model.dart';
import '../core/models/citizen_report.dart';
import '../core/models/exposure_asset.dart';
import '../core/models/priority_item.dart';
import '../core/models/region_summary.dart';
import '../core/models/risk_data.dart';
import '../core/models/user_profile.dart';
import '../data/repositories/risk_repository.dart';
import '../data/services/offline_sync_service.dart';

class AppState extends ChangeNotifier {
  final RiskEngine _riskEngine;
  final BackendClient _backendClient;

  late final RiskRepository _repository;
  late final OfflineSyncService _offlineService;

  // ---------------------------------------------------------------------------
  // CURRENT USER / ROLE
  // ---------------------------------------------------------------------------

  UserProfile _currentUser = const UserProfile(
    id: 'usr_001',
    name: 'Er. Talo Koyu',
    emailOrPhone: 'official@arunachal.gov.in',
    role: UserRole.authority,
    designation: 'Director, State Disaster Management Authority',
    assignedRegion: 'Papum Pare District',
    badgeNumber: 'SDMA-NER-889',
  );

  // ---------------------------------------------------------------------------
  // SELECTED LOCATION
  // ---------------------------------------------------------------------------

  String _selectedLocationId = 'loc_papum_pare';

  // ---------------------------------------------------------------------------
  // STATE CACHES
  // ---------------------------------------------------------------------------

  List<RiskLocation> _locations = [];
  List<ExposureAsset> _assets = [];
  List<PriorityItem> _priorityQueue = [];
  List<ActionItem> _actions = [];
  List<AlertModel> _alerts = [];
  List<CitizenReport> _reports = [];
  List<DistrictRiskSummary> _districtSummaries = [];
  List<RegionHistoryEntry> _regionHistory = [];

  // ---------------------------------------------------------------------------
  // MAP LAYER TOGGLES
  // ---------------------------------------------------------------------------

  bool _layerRiskZones = true;
  bool _layerRoads = true;
  bool _layerRainfall = true;
  bool _layerSoilMoisture = true;
  bool _layerHistoricalLandslides = true;
  bool _layerInfrastructure = true;
  bool _layerCitizenReports = true;

  // ---------------------------------------------------------------------------
  // LOADING / ERROR
  // ---------------------------------------------------------------------------

  bool _isLoading = true;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // LANGUAGE / LOCALE
  // ---------------------------------------------------------------------------

  /// BCP-47 locale tag of the currently selected language.
  /// Supported: 'en', 'hi', 'as', 'bn', 'ne', 'brx'.
  String _selectedLocale = 'en';

  // ---------------------------------------------------------------------------
  // SETTINGS FILE PERSISTENCE
  // ---------------------------------------------------------------------------

  File _getSettingsFile() {
    final tempDir = Directory.systemTemp;
    return File('${tempDir.path}/geonex_app_settings.json');
  }

  Future<void> _loadSettings() async {
    try {
      final file = _getSettingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          if (data['locale'] is String && (data['locale'] as String).isNotEmpty) {
            _selectedLocale = data['locale'] as String;
          }
          if (data['layerRiskZones'] is bool) {
            _layerRiskZones = data['layerRiskZones'] as bool;
          }
          if (data['layerRoads'] is bool) {
            _layerRoads = data['layerRoads'] as bool;
          }
          if (data['layerRainfall'] is bool) {
            _layerRainfall = data['layerRainfall'] as bool;
          }
          if (data['layerSoilMoisture'] is bool) {
            _layerSoilMoisture = data['layerSoilMoisture'] as bool;
          }
          if (data['layerHistoricalLandslides'] is bool) {
            _layerHistoricalLandslides = data['layerHistoricalLandslides'] as bool;
          }
          if (data['layerInfrastructure'] is bool) {
            _layerInfrastructure = data['layerInfrastructure'] as bool;
          }
          if (data['layerCitizenReports'] is bool) {
            _layerCitizenReports = data['layerCitizenReports'] as bool;
          }
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final file = _getSettingsFile();
      final data = {
        'locale': _selectedLocale,
        'layerRiskZones': _layerRiskZones,
        'layerRoads': _layerRoads,
        'layerRainfall': _layerRainfall,
        'layerSoilMoisture': _layerSoilMoisture,
        'layerHistoricalLandslides': _layerHistoricalLandslides,
        'layerInfrastructure': _layerInfrastructure,
        'layerCitizenReports': _layerCitizenReports,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------

  AppState({
    RiskEngine? riskEngine,
    BackendClient? backendClient,
  })  : _riskEngine = riskEngine ?? FutureRiskApiEngine(),
        _backendClient = backendClient ?? MockBackendClient() {
    _repository = RiskRepository(_backendClient);
    _offlineService = OfflineSyncService(_repository);

    _loadSettings();
    loadAllData();
  }

  // ---------------------------------------------------------------------------
  // SET AUTHENTICATED USER (called after real login)
  // ---------------------------------------------------------------------------

  void setAuthenticatedUser(UserProfile profile) {
    _currentUser = profile;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SET LOCALE (called from Settings language picker)
  // ---------------------------------------------------------------------------

  void setLocale(String localeTag) {
    if (_selectedLocale == localeTag) return;
    _selectedLocale = localeTag;
    _saveSettings();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------

  UserProfile get currentUser => _currentUser;

  UserRole get currentRole => _currentUser.role;

  String get selectedLocationId => _selectedLocationId;

  RiskEngine get riskEngine => _riskEngine;

  BackendClient get backendClient => _backendClient;

  List<RiskLocation> get locations => _locations;

  List<ExposureAsset> get assets => _assets;

  List<PriorityItem> get priorityQueue => _priorityQueue;

  List<ActionItem> get actions => _actions;

  List<AlertModel> get alerts => _alerts;

  List<CitizenReport> get reports => _reports;

  List<DistrictRiskSummary> get districtSummaries => _districtSummaries;

  List<RegionHistoryEntry> get regionHistory => _regionHistory;

  RiskRepository get repository => _repository;

  OfflineSyncService get offlineService => _offlineService;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String get selectedLocale => _selectedLocale;


  // ---------------------------------------------------------------------------
  // SELECTED LOCATION
  // ---------------------------------------------------------------------------

  RiskLocation? get selectedLocation {
    for (final location in _locations) {
      if (location.id == _selectedLocationId) {
        return location;
      }
    }

    if (_locations.isNotEmpty) {
      return _locations.first;
    }

    return null;
  }

  List<ExposureAsset> get selectedLocationAssets {
    return _assets
        .where((asset) => asset.locationId == _selectedLocationId)
        .toList();
  }

  List<ActionItem> get selectedLocationActions {
    return _actions
        .where((action) => action.locationId == _selectedLocationId)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // MAP LAYER GETTERS
  // ---------------------------------------------------------------------------

  bool get layerRiskZones => _layerRiskZones;

  bool get layerRoads => _layerRoads;

  bool get layerRainfall => _layerRainfall;

  bool get layerSoilMoisture => _layerSoilMoisture;

  bool get layerHistoricalLandslides => _layerHistoricalLandslides;

  bool get layerInfrastructure => _layerInfrastructure;

  bool get layerCitizenReports => _layerCitizenReports;

  // ---------------------------------------------------------------------------
  // USER ROLE
  // ---------------------------------------------------------------------------

  void switchUserRole(UserRole newRole) {
    if (newRole == UserRole.authority) {
      _currentUser = const UserProfile(
        id: 'usr_001',
        name: 'Er. Talo Koyu',
        emailOrPhone: 'official@arunachal.gov.in',
        role: UserRole.authority,
        designation: 'Director, State Disaster Management Authority',
        assignedRegion: 'Papum Pare District',
        badgeNumber: 'SDMA-NER-889',
      );
    } else if (newRole == UserRole.fieldOfficer) {
      _currentUser = const UserProfile(
        id: 'usr_002',
        name: 'Inspector Tayeng',
        emailOrPhone: 'tayeng.field@disaster.in',
        role: UserRole.fieldOfficer,
        designation: 'Field Inspection Lead, Rapid Response Unit',
        assignedRegion: 'Papum Pare & Subansiri Corridors',
        badgeNumber: 'FO-AR-402',
      );
    } else {
      _currentUser = const UserProfile(
        id: 'usr_003',
        name: 'Taba Nabam',
        emailOrPhone: 'citizen.reporter@gmail.com',
        role: UserRole.citizen,
        designation: 'Verified Community Reporter & Volunteer',
        assignedRegion: 'Doimukh Ward, Papum Pare',
        badgeNumber: 'CITIZEN-NER-109',
      );
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SELECT LOCATION
  // ---------------------------------------------------------------------------

  void selectLocation(String locationId) {
    final exists = _locations.any((location) => location.id == locationId);

    if (!exists) {
      return;
    }

    if (_selectedLocationId == locationId) {
      return;
    }

    _selectedLocationId = locationId;

    notifyListeners();

    loadHistoryForSelected();
  }

  // ---------------------------------------------------------------------------
  // MAP LAYER TOGGLE
  // ---------------------------------------------------------------------------

  void toggleLayer(String layerKey) {
    switch (layerKey) {
      case 'riskZones':
        _layerRiskZones = !_layerRiskZones;
        break;

      case 'roads':
        _layerRoads = !_layerRoads;
        break;

      case 'rainfall':
        _layerRainfall = !_layerRainfall;
        break;

      case 'soilMoisture':
        _layerSoilMoisture = !_layerSoilMoisture;
        break;

      case 'historicalLandslides':
        _layerHistoricalLandslides =
            !_layerHistoricalLandslides;
        break;

      case 'infrastructure':
        _layerInfrastructure = !_layerInfrastructure;
        break;

      case 'citizenReports':
        _layerCitizenReports = !_layerCitizenReports;
        break;
    }

    _saveSettings();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // LOAD ALL DATA
  // ---------------------------------------------------------------------------

  Future<void> loadAllData() async {
    _isLoading = true;
    _errorMessage = null;

    notifyListeners();

    try {
      // ---------------------------------------------------------------
      // LOCATIONS
      // ---------------------------------------------------------------

      _locations = await _repository.getLocations();

      if (_locations.isNotEmpty) {
        // Make sure the currently selected location actually exists.
        final selectedExists = _locations.any(
          (location) => location.id == _selectedLocationId,
        );

        if (!selectedExists) {
          _selectedLocationId = _locations.first.id;
        }

        // -------------------------------------------------------------
        // ML RISK CALCULATION
        // -------------------------------------------------------------

        final riskResults =
            await _riskEngine.calculateBatchRisk(_locations);

        _locations = _locations.map((location) {
          final result = riskResults[location.id];

          if (result == null) {
            return location;
          }

          return RiskLocation(
            id: location.id,
            name: location.name,
            district: location.district,
            state: location.state,
            latitude: location.latitude,
            longitude: location.longitude,
            susceptibility: location.susceptibility,
            dynamicConditions: location.dynamicConditions,
            calculatedResult: result,
          );
        }).toList();
      }

      // ---------------------------------------------------------------
      // OTHER DATA
      // ---------------------------------------------------------------

      _assets = await _repository.getAssets();

      _priorityQueue = await _repository.getPriorityQueue();

      _actions = await _repository.getActions();

      _alerts = await _repository.getAlerts();

      _reports = await _repository.getReports();

      _districtSummaries =
          await _repository.getDistrictSummaries();

      // ---------------------------------------------------------------
      // HISTORY
      // ---------------------------------------------------------------

      final selected = selectedLocation;

      if (selected != null) {
        _regionHistory =
            await _repository.getDistrictHistory(selected.district);
      }

      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      // This is important.
      // Dashboard will no longer remain on the loading spinner forever.
      _isLoading = false;

      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // LOAD HISTORY FOR SELECTED LOCATION
  // ---------------------------------------------------------------------------

  Future<void> loadHistoryForSelected() async {
    final selected = selectedLocation;

    if (selected == null) {
      return;
    }

    try {
      _regionHistory =
          await _repository.getDistrictHistory(selected.district);

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // ACTION LIFECYCLE
  // ---------------------------------------------------------------------------

  Future<void> updateActionStatus(
    String actionId,
    ActionStatus newStatus, {
    String? notes,
  }) async {
    await _repository.updateActionStatus(
      actionId,
      newStatus,
      notes: notes,
    );

    _actions = await _repository.getActions();

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // CITIZEN REPORT SUBMISSION
  // ---------------------------------------------------------------------------

  Future<void> submitCitizenReport(
    CitizenReport report,
  ) async {
    if (_offlineService.isOnline) {
      await _repository.submitReport(report);

      _reports = await _repository.getReports();
    } else {
      await _offlineService.enqueueReport(report);
    }

    // ---------------------------------------------------------------
    // IN-APP NOTIFICATION: PENDING CITIZEN REPORT
    // ---------------------------------------------------------------
    final reportDisplayId = report.reportId.length > 8
        ? report.reportId.substring(0, 8)
        : report.reportId;

    final pendingAlert = AlertModel(
      alertId: 'alt_rpt_${DateTime.now().millisecondsSinceEpoch}',
      locationId: _selectedLocationId,
      locationName: report.locationName,
      region: 'Papum Pare, Arunachal Pradesh',
      severity: report.severity,
      title: 'NEW CITIZEN REPORT #$reportDisplayId PENDING',
      message:
          'Citizen ${report.submittedBy} reported ${report.incidentType.displayName} at ${report.locationName}. Awaiting field verification.',
      cause: 'Citizen Ground Truth Submission',
      recommendedAction:
          'Dispatch Field Officer for on-ground verification',
      createdAt: DateTime.now(),
      status: AlertStatus.active,
      deliveryChannels: const [
        DeliveryChannel.push,
        DeliveryChannel.sms,
      ],
      previousRiskScore: 0,
      currentRiskScore: 0,
    );

    await _repository.createAlert(pendingAlert);
    _alerts = await _repository.getAlerts();

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // FIELD VERIFICATION
  // ---------------------------------------------------------------------------

  Future<void> verifyFieldReport(
    String reportId,
    ReportVerificationStatus status, {
    String? notes,
  }) async {
    await _repository.verifyReport(
      reportId,
      status,
      verifiedBy: _currentUser.name,
      notes: notes,
    );

    // Refresh data after verification.
    _reports = await _repository.getReports();

    _locations = await _repository.getLocations();

    _priorityQueue =
        await _repository.getPriorityQueue();

    _alerts = await _repository.getAlerts();

    _districtSummaries =
        await _repository.getDistrictSummaries();

    final targetReport = _reports.firstWhere(
      (report) => report.reportId == reportId,
      orElse: () => _reports.first,
    );

    final reportDisplayId = targetReport.reportId.length > 8
        ? targetReport.reportId.substring(0, 8)
        : targetReport.reportId;

    // ---------------------------------------------------------------
    // IN-APP NOTIFICATIONS TIED TO REAL STATE TRANSITIONS
    // ---------------------------------------------------------------

    if (status == ReportVerificationStatus.verified) {
      final newAlert = AlertModel(
        alertId:
            'alt_ver_${DateTime.now().millisecondsSinceEpoch}',
        locationId: _selectedLocationId,
        locationName: targetReport.locationName,
        region: 'Papum Pare, Arunachal Pradesh',
        severity: targetReport.severity,
        title:
            'VERIFIED ${targetReport.incidentType.displayName.toUpperCase()} CONFIRMED',
        message:
            'Field Officer ${_currentUser.name} verified report #$reportDisplayId: ${notes != null && notes.isNotEmpty ? notes : targetReport.notes}',
        cause: 'Field Ground Truth Verification',
        recommendedAction:
            'Dispatch Road Clearance Team & Update Hazard Zoning',
        createdAt: DateTime.now(),
        status: AlertStatus.active,
        deliveryChannels: const [
          DeliveryChannel.push,
          DeliveryChannel.sms,
          DeliveryChannel.broadcastSiren,
          DeliveryChannel.capIntegration,
        ],
        previousRiskScore: 78,
        currentRiskScore: 92,
      );

      await _repository.createAlert(newAlert);
      _alerts = await _repository.getAlerts();
    } else if (status == ReportVerificationStatus.rejected) {
      final rejectAlert = AlertModel(
        alertId: 'alt_rej_${DateTime.now().millisecondsSinceEpoch}',
        locationId: _selectedLocationId,
        locationName: targetReport.locationName,
        region: 'Papum Pare, Arunachal Pradesh',
        severity: SeverityLevel.low,
        title: 'REPORT REJECTED — ${targetReport.incidentType.displayName}',
        message:
            'Field Officer ${_currentUser.name} rejected report #$reportDisplayId.'
            '${notes != null && notes.isNotEmpty ? " Reason: $notes" : ""}',
        cause: 'Insufficient Ground Evidence',
        recommendedAction: 'Resubmit with additional media if conditions persist.',
        createdAt: DateTime.now(),
        status: AlertStatus.active,
        deliveryChannels: const [DeliveryChannel.push],
        previousRiskScore: 0,
        currentRiskScore: 0,
      );

      await _repository.createAlert(rejectAlert);
      _alerts = await _repository.getAlerts();
    } else if (status == ReportVerificationStatus.escalated) {
      final needsInfoAlert = AlertModel(
        alertId: 'alt_info_${DateTime.now().millisecondsSinceEpoch}',
        locationId: _selectedLocationId,
        locationName: targetReport.locationName,
        region: 'Papum Pare, Arunachal Pradesh',
        severity: SeverityLevel.medium,
        title: 'REPORT NEEDS INFO — ${targetReport.incidentType.displayName}',
        message:
            'Field Officer ${_currentUser.name} requested additional evidence for report #$reportDisplayId.'
            '${notes != null && notes.isNotEmpty ? " Notes: $notes" : ""}',
        cause: 'Field Assessment Clarification',
        recommendedAction: 'Attach high-resolution photos and GPS coordinates.',
        createdAt: DateTime.now(),
        status: AlertStatus.active,
        deliveryChannels: const [DeliveryChannel.push, DeliveryChannel.sms],
        previousRiskScore: 0,
        currentRiskScore: 0,
      );

      await _repository.createAlert(needsInfoAlert);
      _alerts = await _repository.getAlerts();
    }

    notifyListeners();
  }


  // ---------------------------------------------------------------------------
  // DYNAMIC FACTOR SIMULATION
  // ---------------------------------------------------------------------------

  Future<void> simulateDynamicChange({
    required String locationId,
    required double rainfallMm,
    required double soilMoistureIndex,
  }) async {
    final loc = _locations.firstWhere(
      (location) => location.id == locationId,
    );

    final updatedConditions =
        loc.dynamicConditions.copyWith(
      rainfallMm: rainfallMm,
      soilMoistureIndex: soilMoistureIndex,
    );

    await _repository.updateDynamicFactors(
      locationId,
      updatedConditions,
    );

    _locations = await _repository.getLocations();

    _priorityQueue =
        await _repository.getPriorityQueue();

    _districtSummaries =
        await _repository.getDistrictSummaries();

    notifyListeners();
  }
}