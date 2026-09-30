import '../constants/app_constants.dart';

class CitizenReport {
  final String reportId;
  final String locationName;
  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final String mediaPath; // actual file path or URL
  final IncidentType incidentType;
  final SeverityLevel severity;
  final String notes;
  final ReportVerificationStatus verificationStatus;
  final String submittedBy;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? verificationNotes;
  final bool isOfflineQueued;
  final Map<String, dynamic>? validationResult;
  final List<Map<String, dynamic>>? mediaList;

  const CitizenReport({
    required this.reportId,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.mediaPath,
    required this.incidentType,
    required this.severity,
    required this.notes,
    required this.verificationStatus,
    required this.submittedBy,
    this.verifiedBy,
    this.verifiedAt,
    this.verificationNotes,
    this.isOfflineQueued = false,
    this.validationResult,
    this.mediaList,
  });

  CitizenReport copyWith({
    String? reportId,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
    String? mediaPath,
    IncidentType? incidentType,
    SeverityLevel? severity,
    String? notes,
    ReportVerificationStatus? verificationStatus,
    String? submittedBy,
    String? verifiedBy,
    DateTime? verifiedAt,
    String? verificationNotes,
    bool? isOfflineQueued,
    Map<String, dynamic>? validationResult,
    List<Map<String, dynamic>>? mediaList,
  }) {
    return CitizenReport(
      reportId: reportId ?? this.reportId,
      locationName: locationName ?? this.locationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      capturedAt: capturedAt ?? this.capturedAt,
      mediaPath: mediaPath ?? this.mediaPath,
      incidentType: incidentType ?? this.incidentType,
      severity: severity ?? this.severity,
      notes: notes ?? this.notes,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      submittedBy: submittedBy ?? this.submittedBy,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      verificationNotes: verificationNotes ?? this.verificationNotes,
      isOfflineQueued: isOfflineQueued ?? this.isOfflineQueued,
      validationResult: validationResult ?? this.validationResult,
      mediaList: mediaList ?? this.mediaList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reportId': reportId,
      'locationName': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'capturedAt': capturedAt.toIso8601String(),
      'mediaPath': mediaPath,
      'incidentType': incidentType.name,
      'severity': severity.name,
      'notes': notes,
      'verificationStatus': verificationStatus.name,
      'submittedBy': submittedBy,
      'verifiedBy': verifiedBy,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'verificationNotes': verificationNotes,
      'isOfflineQueued': isOfflineQueued,
      'validationResult': validationResult,
      'mediaList': mediaList,
    };
  }

  factory CitizenReport.fromJson(Map<String, dynamic> json) {
    return CitizenReport(
      reportId: json['reportId'] as String? ?? '',
      locationName: json['locationName'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      capturedAt: json['capturedAt'] != null
          ? DateTime.tryParse(json['capturedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      mediaPath: json['mediaPath'] as String? ?? '',
      incidentType: IncidentType.values.firstWhere(
        (e) => e.name == json['incidentType'],
        orElse: () => IncidentType.landslide,
      ),
      severity: SeverityLevel.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => SeverityLevel.medium,
      ),
      notes: json['notes'] as String? ?? '',
      verificationStatus: ReportVerificationStatus.values.firstWhere(
        (e) => e.name == json['verificationStatus'],
        orElse: () => ReportVerificationStatus.pendingUpload,
      ),
      submittedBy: json['submittedBy'] as String? ?? '',
      verifiedBy: json['verifiedBy'] as String?,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String)
          : null,
      verificationNotes: json['verificationNotes'] as String?,
      isOfflineQueued: json['isOfflineQueued'] as bool? ?? false,
      validationResult: json['validationResult'] as Map<String, dynamic>?,
      mediaList: (json['mediaList'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
    );
  }
}

