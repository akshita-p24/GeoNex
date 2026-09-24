from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from app.core.enums import (
    LifecycleStatus,
    Severity,
    TERMINAL_LIFECYCLE_STATUSES,
)
from app.models.alert import Alert, AlertStatus
from app.models.risk_prediction import RiskLevel


@dataclass
class TransitionOutcome:
    severity_changed: bool
    direction: Optional[str]
    new_severity: Optional[Severity]
    lifecycle_changed: bool
    new_lifecycle: Optional[LifecycleStatus]


def severity_to_risk_level(severity: Severity) -> RiskLevel:
    """
    Convert M5 Severity to the legacy M3 RiskLevel.

    M5 uses NORMAL where M3 uses LOW.
    """

    mapping = {
        Severity.NORMAL: RiskLevel.LOW,
        Severity.WATCH: RiskLevel.WATCH,
        Severity.WARNING: RiskLevel.WARNING,
        Severity.CRITICAL: RiskLevel.CRITICAL,
    }

    return mapping[severity]


def apply_confirmed_transition(
    alert: Alert,
    confirmed_severity: Severity,
    direction: str,
    prediction_timestamp: datetime,
) -> TransitionOutcome:
    """
    Apply a persistence-confirmed severity transition.

    Both M5 current_severity and the legacy M3 severity
    are kept synchronized.
    """

    if alert.lifecycle_status in TERMINAL_LIFECYCLE_STATUSES:
        raise ValueError(
            "apply_confirmed_transition called on a terminal "
            "alert; this is a caller bug"
        )

    # Update M5 severity.
    alert.current_severity = confirmed_severity

    # Update legacy M3 severity.
    alert.severity = severity_to_risk_level(
        confirmed_severity
    )

    # Record when this severity band was entered.
    alert.band_entered_at = prediction_timestamp

    lifecycle_changed = False
    new_lifecycle = None

    if direction == "resolve":
        alert.lifecycle_status = LifecycleStatus.RESOLVED
        alert.status = AlertStatus.RESOLVED
        alert.resolved_at = prediction_timestamp

        lifecycle_changed = True
        new_lifecycle = LifecycleStatus.RESOLVED

    return TransitionOutcome(
        severity_changed=True,
        direction=direction,
        new_severity=confirmed_severity,
        lifecycle_changed=lifecycle_changed,
        new_lifecycle=new_lifecycle,
    )


def is_stale(
    alert: Alert,
    now: datetime,
    max_gap_seconds: int,
) -> bool:
    """
    Check whether an active alert has stopped receiving
    predictions for longer than the allowed gap.
    """

    if alert.lifecycle_status not in (
        LifecycleStatus.ACTIVE,
        LifecycleStatus.ACKNOWLEDGED,
    ):
        return False

    reference = (
        alert.last_prediction_timestamp
        or alert.created_at
    )

    if reference is None:
        return False

    return (
        now - reference
    ).total_seconds() > max_gap_seconds


def apply_expiration(
    alert: Alert,
    now: datetime,
) -> TransitionOutcome:
    """
    Mark an active alert as expired.
    """

    alert.lifecycle_status = LifecycleStatus.EXPIRED
    alert.status = AlertStatus.EXPIRED
    alert.expired_at = now

    return TransitionOutcome(
        severity_changed=False,
        direction=None,
        new_severity=None,
        lifecycle_changed=True,
        new_lifecycle=LifecycleStatus.EXPIRED,
    )
