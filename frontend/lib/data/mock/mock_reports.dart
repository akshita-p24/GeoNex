import '../../core/constants/app_constants.dart';
import '../../core/models/citizen_report.dart';

class MockReportsData {
  static List<CitizenReport> getInitialReports() {
    return [
      CitizenReport(
        reportId: 'report_001',
        locationName: 'NH-415, Papum Pare',
        latitude: 27.1420,
        longitude: 93.6920,
        capturedAt: DateTime(2026, 9, 20, 9, 30),
        mediaPath: 'mock://report_001.jpg',
        incidentType: IncidentType.landslide,
        severity: SeverityLevel.high,
        notes:
            'Visible slope failure and debris accumulation near the road.',
        verificationStatus: ReportVerificationStatus.verified,
        submittedBy: 'citizen_001',
        verifiedBy: 'Er. Talo Koyu',
        verifiedAt: DateTime(2026, 9, 20, 11, 15),
        verificationNotes: 'Field verification completed.',
      ),
      CitizenReport(
        reportId: 'report_002',
        locationName: 'Nirjuli Ridge',
        latitude: 27.1390,
        longitude: 93.7120,
        capturedAt: DateTime(2026, 9, 21, 14, 10),
        mediaPath: 'mock://report_002.jpg',
        incidentType: IncidentType.crack,
        severity: SeverityLevel.medium,
        notes:
            'Ground cracks observed along the roadside slope.',
        verificationStatus: ReportVerificationStatus.pendingUpload,
        submittedBy: 'citizen_002',
        isOfflineQueued: true,
      ),
      CitizenReport(
        reportId: 'report_003',
        locationName: 'East Valley Link',
        latitude: 27.1510,
        longitude: 93.7190,
        capturedAt: DateTime(2026, 9, 22, 8, 45),
        mediaPath: 'mock://report_003.jpg',
        incidentType: IncidentType.roadBlockage,
        severity: SeverityLevel.high,
        notes:
            'Loose debris partially blocking the road.',
        verificationStatus: ReportVerificationStatus.uploaded,
        submittedBy: 'citizen_003',
      ),
      CitizenReport(
        reportId: 'report_004',
        locationName: 'Forest Gate',
        latitude: 27.1460,
        longitude: 93.7080,
        capturedAt: DateTime(2026, 9, 23, 16, 20),
        mediaPath: 'mock://report_004.jpg',
        incidentType: IncidentType.slopeMovement,
        severity: SeverityLevel.low,
        notes:
            'Minor soil movement observed on the upper slope.',
        verificationStatus: ReportVerificationStatus.rejected,
        submittedBy: 'citizen_004',
        verifiedBy: 'Er. Talo Koyu',
        verifiedAt: DateTime(2026, 9, 23, 18, 00),
        verificationNotes:
            'Evidence insufficient for confirmation.',
      ),
    ];
  }
}