"""
app/models/__init__.py

Exports all models so Alembic can find them for migrations.
Every model must be imported here.
"""

from app.models.user import User, UserRole

from app.models.field_report import (
    FieldReport,
    ReportType,
    ReportStatus,
)

from app.models.media import (
    Media,
    MediaType,
)

from app.models.field_verification import (
    FieldVerification,
    VerificationDecision,
)

from app.models.landslide_inventory import LandslideInventory

from app.models.risk_prediction import (
    RiskPrediction,
    RiskLevel,
)

from app.models.observation import (
    RainfallObservation,
    SoilMoistureObservation,
    SARObservation,
)

from app.models.earthquake import EarthquakeEvent

from app.models.spatial import (
    Road,
    Village,
    Infrastructure,
    InfrastructureCategory,
)

from app.models.alert import (
    Alert,
    AlertDelivery,
    AlertStatus,
    DeliveryChannel,
    DeliveryStatus,
)

from app.models.model_version import ModelVersion

from app.models.audit_log import AuditLog

# M5 alerting models
from app.models.alert_audit_log import AlertAuditLog
from app.models.alert_config import AlertConfig
from app.models.notification import NotificationIntent
from app.models.notification_cooldown import NotificationCooldown
from app.models.notification_subscription import NotificationSubscription
from app.models.processed_risk_event import ProcessedRiskEvent

# M6 / IoT models
from app.models.iot import (
    IoTSensorNode,
    IoTSensorReading,
)


__all__ = [
    "User",
    "UserRole",

    "FieldReport",
    "ReportType",
    "ReportStatus",

    "Media",
    "MediaType",

    "FieldVerification",
    "VerificationDecision",

    "LandslideInventory",

    "RiskPrediction",
    "RiskLevel",

    "RainfallObservation",
    "SoilMoistureObservation",
    "SARObservation",

    "EarthquakeEvent",

    "Road",
    "Village",
    "Infrastructure",
    "InfrastructureCategory",

    "Alert",
    "AlertDelivery",
    "AlertStatus",
    "DeliveryChannel",
    "DeliveryStatus",

    "ModelVersion",

    "AuditLog",

    # M5
    "AlertAuditLog",
    "AlertConfig",
    "NotificationIntent",
    "NotificationCooldown",
    "NotificationSubscription",
    "ProcessedRiskEvent",

    # IoT
    "IoTSensorNode",
    "IoTSensorReading",
]