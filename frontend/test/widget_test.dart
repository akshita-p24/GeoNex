import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_risk_to_action/ai/mock_risk_engine.dart';
import 'package:sih_risk_to_action/backend/mock_backend_client.dart';
import 'package:sih_risk_to_action/core/constants/app_constants.dart';
import 'package:sih_risk_to_action/core/models/citizen_report.dart';
import 'package:sih_risk_to_action/core/models/risk_data.dart';
import 'package:sih_risk_to_action/core/models/user_profile.dart';
import 'package:sih_risk_to_action/localization/app_localizations.dart';
import 'package:sih_risk_to_action/state/app_state.dart';

void main() {
  const riskEngine = MockRiskEngine();

  group('TEST A — Map Layers', () {
    test('All map layers can be toggled independently in AppState', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      // Initial defaults are true
      expect(appState.layerRiskZones, isTrue);
      expect(appState.layerRoads, isTrue);
      expect(appState.layerRainfall, isTrue);
      expect(appState.layerSoilMoisture, isTrue);
      expect(appState.layerHistoricalLandslides, isTrue);
      expect(appState.layerInfrastructure, isTrue);
      expect(appState.layerCitizenReports, isTrue);

      // Toggle risk zones off
      appState.toggleLayer('riskZones');
      expect(appState.layerRiskZones, isFalse);
      // Other layers remain untouched
      expect(appState.layerRoads, isTrue);
      expect(appState.layerRainfall, isTrue);

      // Toggle roads off
      appState.toggleLayer('roads');
      expect(appState.layerRoads, isFalse);
      expect(appState.layerRiskZones, isFalse);

      // Toggle rainfall off
      appState.toggleLayer('rainfall');
      expect(appState.layerRainfall, isFalse);

      // Toggle soil moisture off
      appState.toggleLayer('soilMoisture');
      expect(appState.layerSoilMoisture, isFalse);

      // Toggle historical landslides off
      appState.toggleLayer('historicalLandslides');
      expect(appState.layerHistoricalLandslides, isFalse);

      // Toggle infrastructure off
      appState.toggleLayer('infrastructure');
      expect(appState.layerInfrastructure, isFalse);

      // Toggle citizen reports off
      appState.toggleLayer('citizenReports');
      expect(appState.layerCitizenReports, isFalse);

      // Toggle all back on
      appState.toggleLayer('riskZones');
      appState.toggleLayer('roads');
      appState.toggleLayer('rainfall');
      appState.toggleLayer('soilMoisture');
      appState.toggleLayer('historicalLandslides');
      appState.toggleLayer('infrastructure');
      appState.toggleLayer('citizenReports');

      expect(appState.layerRiskZones, isTrue);
      expect(appState.layerRoads, isTrue);
      expect(appState.layerRainfall, isTrue);
      expect(appState.layerSoilMoisture, isTrue);
      expect(appState.layerHistoricalLandslides, isTrue);
      expect(appState.layerInfrastructure, isTrue);
      expect(appState.layerCitizenReports, isTrue);
    });

    test('Citizen Reports and Infrastructure have valid coordinate data', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      // Verify reports have real coordinates
      final reportsWithCoords = appState.reports
          .where((r) => r.latitude != 0.0 && r.longitude != 0.0)
          .toList();
      expect(reportsWithCoords.isNotEmpty, isTrue);
      for (final r in reportsWithCoords) {
        expect(r.latitude, inInclusiveRange(20.0, 35.0));
        expect(r.longitude, inInclusiveRange(85.0, 100.0));
      }

      // Verify assets have real coordinates
      final assetsWithCoords = appState.assets
          .where((a) => a.latitude != 0.0 && a.longitude != 0.0)
          .toList();
      expect(assetsWithCoords.isNotEmpty, isTrue);
    });
  });

  group('TEST C — Language & Localization', () {
    test('AppState setLocale updates selectedLocale and triggers listeners', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      expect(appState.selectedLocale, equals('en'));

      bool listenerCalled = false;
      appState.addListener(() => listenerCalled = true);

      appState.setLocale('hi');
      expect(appState.selectedLocale, equals('hi'));
      expect(listenerCalled, isTrue);

      appState.setLocale('as');
      expect(appState.selectedLocale, equals('as'));

      appState.setLocale('bn');
      expect(appState.selectedLocale, equals('bn'));

      appState.setLocale('ne');
      expect(appState.selectedLocale, equals('ne'));

      appState.setLocale('brx');
      expect(appState.selectedLocale, equals('brx'));
    });

    test('AppLocalizations returns correct translations for all supported locales', () {
      final enLoc = AppLocalizations(const Locale('en'));
      expect(enLoc.navDashboard, equals('Dashboard'));
      expect(enLoc.riskOverview, equals('Risk Overview'));
      expect(enLoc.settingsTitle, equals('Profile / Settings'));

      final hiLoc = AppLocalizations(const Locale('hi'));
      expect(hiLoc.navDashboard, equals('डैशबोर्ड'));
      expect(hiLoc.riskOverview, equals('जोखिम अवलोकन'));
      expect(hiLoc.verify, equals('सत्यापित करें'));

      final asLoc = AppLocalizations(const Locale('as'));
      expect(asLoc.navDashboard, equals('ড্যাশব\'ৰ্ড'));
      expect(asLoc.navRiskMap, equals('বিপদ মানচিত্ৰ'));

      final bnLoc = AppLocalizations(const Locale('bn'));
      expect(bnLoc.navDashboard, equals('ড্যাশবোর্ড'));
      expect(bnLoc.navRiskMap, equals('ঝুঁকি মানচিত্র'));

      final neLoc = AppLocalizations(const Locale('ne'));
      expect(neLoc.navDashboard, equals('ड्यासबोर्ड'));
      expect(neLoc.navRiskMap, equals('जोखिम नक्सा'));

      final brxLoc = AppLocalizations(const Locale('brx'));
      expect(brxLoc.navDashboard, equals('ड्यासबर\'ड'));
      expect(brxLoc.navRiskMap, equals('बिफाव मनखोन'));
    });
  });

  group('TEST D & F — Notifications & Complete End-to-End Workflow', () {
    test('Citizen report submission generates real PENDING in-app notification', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      final initialAlertsCount = appState.alerts.length;

      final newReport = CitizenReport(
        reportId: 'rpt_test_001',
        locationName: 'Doimukh Road Section 4',
        latitude: 27.1450,
        longitude: 93.6950,
        capturedAt: DateTime.now(),
        mediaPath: '',
        incidentType: IncidentType.landslide,
        severity: SeverityLevel.high,
        notes: 'Active rockfall on road cutting',
        verificationStatus: ReportVerificationStatus.uploaded,
        submittedBy: 'Taba Nabam',
      );

      await appState.submitCitizenReport(newReport);

      // Verify report was added to reports
      expect(appState.reports.any((r) => r.reportId == 'rpt_test_001'), isTrue);

      // Verify in-app pending alert was generated
      expect(appState.alerts.length, greaterThan(initialAlertsCount));
      final pendingAlert = appState.alerts.firstWhere(
        (a) => a.title.contains('PENDING'),
      );
      expect(pendingAlert.title, contains('rpt_test_001'));
      expect(pendingAlert.message, contains('Taba Nabam'));
      expect(pendingAlert.status, equals(AlertStatus.active));
    });

    test('Field Officer verification transitions generate real in-app notifications', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      // 1. Submit citizen report
      final report = CitizenReport(
        reportId: 'rpt_test_002',
        locationName: 'Nirjuli Bypass Kilometer 9',
        latitude: 27.1400,
        longitude: 93.7100,
        capturedAt: DateTime.now(),
        mediaPath: '',
        incidentType: IncidentType.crack,
        severity: SeverityLevel.high,
        notes: 'Tension fissure expanding across shoulder',
        verificationStatus: ReportVerificationStatus.uploaded,
        submittedBy: 'Citizen Volunteer',
      );

      await appState.submitCitizenReport(report);

      // Switch role to field officer
      appState.switchUserRole(UserRole.fieldOfficer);
      expect(appState.currentRole, equals(UserRole.fieldOfficer));

      // 2. Field Officer verifies report
      await appState.verifyFieldReport(
        'rpt_test_002',
        ReportVerificationStatus.verified,
        notes: 'Ground confirmed 15cm subsidence.',
      );

      // Verify report status is verified
      final verifiedReport = appState.reports.firstWhere((r) => r.reportId == 'rpt_test_002');
      expect(verifiedReport.verificationStatus, equals(ReportVerificationStatus.verified));

      // Verify VERIFIED in-app alert was generated for Authority
      final verifiedAlert = appState.alerts.firstWhere(
        (a) => a.title.contains('VERIFIED') && a.title.contains('CONFIRMED'),
      );
      expect(verifiedAlert.message, contains('rpt_test_002'));
      expect(verifiedAlert.message, contains('Ground confirmed 15cm subsidence'));

      // Switch role to authority to review
      appState.switchUserRole(UserRole.authority);
      expect(appState.currentRole, equals(UserRole.authority));
      expect(appState.alerts.any((a) => a.title.contains('CONFIRMED')), isTrue);
    });

    test('Field Officer rejection generates real REJECTED in-app notification', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      final report = CitizenReport(
        reportId: 'rpt_test_003',
        locationName: 'Forest Gate Km 2',
        latitude: 27.1460,
        longitude: 93.7080,
        capturedAt: DateTime.now(),
        mediaPath: '',
        incidentType: IncidentType.slopeMovement,
        severity: SeverityLevel.low,
        notes: 'Small debris on verge',
        verificationStatus: ReportVerificationStatus.uploaded,
        submittedBy: 'Passerby',
      );

      await appState.submitCitizenReport(report);

      // Field Officer rejects report
      await appState.verifyFieldReport(
        'rpt_test_003',
        ReportVerificationStatus.rejected,
        notes: 'Superficial debris cleared by maintenance crew. No slope movement.',
      );

      final rejectedReport = appState.reports.firstWhere((r) => r.reportId == 'rpt_test_003');
      expect(rejectedReport.verificationStatus, equals(ReportVerificationStatus.rejected));

      final rejectAlert = appState.alerts.firstWhere(
        (a) => a.title.contains('REPORT REJECTED'),
      );
      expect(rejectAlert.message, contains('rpt_test_003'));
      expect(rejectAlert.message, contains('Superficial debris cleared'));
    });
  });

  group('TEST E — Dashboard Metrics & Computations', () {
    test('Dashboard metrics and priority queues compute without crashing', () async {
      final backend = MockBackendClient(riskEngine: riskEngine);
      final appState = AppState(backendClient: backend, riskEngine: riskEngine);
      await appState.loadAllData();

      expect(appState.isLoading, isFalse);
      expect(appState.locations.isNotEmpty, isTrue);
      expect(appState.priorityQueue.isNotEmpty, isTrue);

      final highRiskCount = appState.locations
          .where((l) => (l.calculatedResult?.riskScore ?? 0) >= 65)
          .length;
      expect(highRiskCount, greaterThanOrEqualTo(0));

      final activeAlerts = appState.alerts
          .where((a) => a.status == AlertStatus.active)
          .toList();
      expect(activeAlerts.isNotEmpty, isTrue);

      final totalPop = appState.assets
          .fold(0, (sum, a) => sum + a.estimatedPopulationAtRisk);
      expect(totalPop, greaterThan(0));
    });
  });
}
