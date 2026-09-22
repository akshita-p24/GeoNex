enum UserRole {
  authority,
  fieldOfficer,
  citizen,
}

enum RiskLevel {
  low,
  moderate,
  high,
  critical,
}

extension RiskLevelExt on RiskLevel {
  String get displayName {
    switch (this) {
      case RiskLevel.low:
        return 'LOW';
      case RiskLevel.moderate:
        return 'MODERATE';
      case RiskLevel.high:
        return 'HIGH';
      case RiskLevel.critical:
        return 'CRITICAL';
    }
  }
}

enum IncidentType {
  landslide,
  crack,
  rockfall,
  roadBlockage,
  slopeMovement,
  debrisFlow,
  other,
}

extension IncidentTypeExt on IncidentType {
  String get displayName {
    switch (this) {
      case IncidentType.landslide:
        return 'Landslide';
      case IncidentType.crack:
        return 'Ground Crack';
      case IncidentType.rockfall:
        return 'Rockfall';
      case IncidentType.roadBlockage:
        return 'Road Blockage';
      case IncidentType.slopeMovement:
        return 'Slope Movement';
      case IncidentType.debrisFlow:
        return 'Debris Flow';
      case IncidentType.other:
        return 'Other Anomaly';
    }
  }
}

enum SeverityLevel {
  low,
  medium,
  high,
  critical,
}

extension SeverityLevelExt on SeverityLevel {
  String get displayName {
    switch (this) {
      case SeverityLevel.low:
        return 'Low';
      case SeverityLevel.medium:
        return 'Medium';
      case SeverityLevel.high:
        return 'High';
      case SeverityLevel.critical:
        return 'Critical';
    }
  }
}

enum ActionType {
  monitor,
  inspect,
  prepare,
  restrict,
  escalate,
}

extension ActionTypeExt on ActionType {
  String get displayName {
    switch (this) {
      case ActionType.monitor:
        return 'Monitor';
      case ActionType.inspect:
        return 'Inspect';
      case ActionType.prepare:
        return 'Prepare';
      case ActionType.restrict:
        return 'Restrict';
      case ActionType.escalate:
        return 'Escalate';
    }
  }
}

enum ActionStatus {
  pending,
  assigned,
  inProgress,
  completed,
}

extension ActionStatusExt on ActionStatus {
  String get displayName {
    switch (this) {
      case ActionStatus.pending:
        return 'Pending';
      case ActionStatus.assigned:
        return 'Assigned';
      case ActionStatus.inProgress:
        return 'In Progress';
      case ActionStatus.completed:
        return 'Completed';
    }
  }
}

enum ReportVerificationStatus {
  draft,
  pendingUpload,
  uploaded,
  verified,
  rejected,
  escalated,
}

enum AlertStatus {
  active,
  resolved,
  expired,
}

enum DeliveryChannel {
  push,
  sms,
  email,
  broadcastSiren,
  capIntegration,
}
