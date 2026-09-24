"""
M5 Alert Engine evaluator.

Consumes an already-created M3 risk prediction and manages:

1. Idempotent risk-event processing
2. Area-level concurrency control
3. Persistence-based escalation/downgrade
4. Alert lifecycle
5. Notification intent creation
6. Audit logging
"""

import logging
from typing import Optional
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import (
    AuditEventType,
    NotificationIntentStatus,
    Severity,
)
from app.core.exceptions import (
    PredictionNotFoundError,
    ProcessingError,
)

from app.models.alert import Alert, AlertStatus
from app.services.alerting import config_service

from app.services.alerting.alert_repo import AlertRepository
from app.services.alerting.audit_repo import AuditRepository
from app.services.alerting.config_repo import ConfigRepository
from app.services.alerting.escalation import (
    template_key_for,
    trigger_type_for_transition,
)
from app.services.alerting.notification_repo import NotificationRepository
from app.services.alerting.persistence import (
    classify_direction,
    evaluate_candidate,
)
from app.services.alerting.risk_event_repo import (
    RiskEventRepository,
)
from app.services.alerting.risk_prediction_repo import (
    M5RiskPrediction,
    RiskPredictionRepository,
)
from app.services.alerting.state_machine import (
    apply_confirmed_transition,
    severity_to_risk_level,
)


logger = logging.getLogger(__name__)


# ============================================================
# HELPERS
# ============================================================

def _severity_from_prediction(
    prediction: M5RiskPrediction,
) -> Severity:
    """
    Convert the M3/M1 risk band into the M5 Severity enum.

    M5 does NOT recalculate the ML risk score.
    It consumes the already-computed risk band.
    """

    try:
        return Severity(prediction.risk_band)

    except ValueError as exc:
        raise ProcessingError(
            f"Unrecognized risk_band "
            f"'{prediction.risk_band}' from M1/M3"
        ) from exc


def _composite_key(
    timestamp,
    created_at,
    prediction_id,
):
    """
    Ordering key used to make prediction processing idempotent.

    A prediction is considered older/equal when this tuple is
    less than or equal to the last evaluated tuple.
    """

    return (
        timestamp,
        created_at,
        prediction_id,
    )


# ============================================================
# PUBLIC ENTRY POINT
# ============================================================

async def process_risk_event(
    prediction_id: UUID,
    session: AsyncSession,
    area_id_hint: Optional[str] = None,
) -> None:
    """
    Main M5 entry point.

    The M3 risk API creates a RiskPrediction first and then calls
    this function.

    M5 then:

        RiskPrediction
              ↓
        claim event
              ↓
        evaluate alert
              ↓
        persistence
              ↓
        transition
              ↓
        notification intent
    """

    prediction_repo = RiskPredictionRepository(session)

    prediction = await prediction_repo.get_with_retry(
        prediction_id
    )

    if prediction is None:
        raise PredictionNotFoundError(
            f"prediction_id={prediction_id} "
            "not visible after retry/backoff"
        )

    risk_event_repo = RiskEventRepository(session)

    area_id = (
        area_id_hint
        if area_id_hint is not None
        else prediction.area_id
    )

    claimed = await risk_event_repo.try_claim(
        prediction.prediction_id,
        area_id=area_id,
        prediction_timestamp=prediction.prediction_timestamp,
    )

    # TXN A:
    # Persist ownership of the event before doing the rest
    # of the alert processing.
    await session.commit()

    if not claimed:
        logger.info(
            "prediction_id=%s already owned/completed, skipping",
            prediction_id,
        )
        return

    await _run_claimed_pipeline(
        prediction,
        session,
        risk_event_repo,
    )


# ============================================================
# PROCESS ALREADY CLAIMED EVENT
# ============================================================

async def process_already_claimed_prediction(
    prediction_id: UUID,
    session: AsyncSession,
) -> None:
    """
    Process a prediction whose processed_risk_events row has
    already been claimed.

    This is useful for retry/reconciliation.
    """

    prediction_repo = RiskPredictionRepository(session)

    prediction = await prediction_repo.get(
        prediction_id
    )

    if prediction is None:
        raise PredictionNotFoundError(
            f"prediction_id={prediction_id} not visible"
        )

    risk_event_repo = RiskEventRepository(session)

    await _run_claimed_pipeline(
        prediction,
        session,
        risk_event_repo,
    )


# ============================================================
# CLAIMED PIPELINE
# ============================================================

async def _run_claimed_pipeline(
    prediction: M5RiskPrediction,
    session: AsyncSession,
    risk_event_repo: RiskEventRepository,
) -> None:
    """
    Execute the actual M5 alert evaluation after the event has
    been successfully claimed.
    """

    try:

        await _evaluate_claimed_prediction(
            prediction,
            session,
        )

        await risk_event_repo.mark_completed(
            prediction.prediction_id
        )

        # TXN B:
        # Alert state + audit + notification intent +
        # processed event completion.
        await session.commit()

    except Exception as exc:

        await session.rollback()

        logger.exception(
            "processing failed for prediction_id=%s",
            prediction.prediction_id,
        )

        try:

            await risk_event_repo.mark_retryable(
                prediction.prediction_id,
                str(exc),
            )

            await session.commit()

        except Exception:

            await session.rollback()

            logger.exception(
                "failed to mark prediction_id=%s retryable",
                prediction.prediction_id,
            )

        raise


# ============================================================
# MAIN EVALUATION
# ============================================================

async def _evaluate_claimed_prediction(
    prediction: M5RiskPrediction,
    session: AsyncSession,
) -> None:
    """
    Evaluate one claimed prediction against the alert state
    for its geographic area.
    """

    alert_repo = AlertRepository(session)

    audit_repo = AuditRepository(session)

    config_repo = ConfigRepository(session)

    notification_repo = NotificationRepository(session)

    # --------------------------------------------------------
    # Serialize evaluations for the same area.
    # --------------------------------------------------------

    await alert_repo.acquire_area_lock(
        prediction.area_id
    )

    # --------------------------------------------------------
    # Convert incoming M3 risk band to M5 severity.
    # --------------------------------------------------------

    incoming_band = _severity_from_prediction(
        prediction
    )

    incoming_key = _composite_key(
        prediction.prediction_timestamp,
        prediction.created_at,
        prediction.prediction_id,
    )

    # --------------------------------------------------------
    # Check whether an open alert already exists.
    # --------------------------------------------------------

    open_alert = await alert_repo.get_open_for_area(
        prediction.area_id
    )

    if open_alert is not None:

        await _evaluate_against_open_alert(
            alert=open_alert,
            prediction=prediction,
            incoming_band=incoming_band,
            incoming_key=incoming_key,
            session=session,
            alert_repo=alert_repo,
            audit_repo=audit_repo,
            config_repo=config_repo,
            notification_repo=notification_repo,
        )

        return

    # --------------------------------------------------------
    # No open alert.
    #
    # Check the latest historical alert so an old prediction
    # cannot create a duplicate/replayed alert.
    # --------------------------------------------------------

    latest_alert = await alert_repo.get_latest_for_area(
        prediction.area_id
    )

    if latest_alert is not None:

        last_key = _composite_key(
            latest_alert.last_evaluated_prediction_timestamp,
            latest_alert.last_evaluated_created_at,
            latest_alert.last_evaluated_prediction_id,
        )

        if (
            last_key[0] is not None
            and incoming_key <= last_key
        ):

            await audit_repo.add_entry(
                latest_alert.alert_id,
                AuditEventType.DUPLICATE_EVENT_IGNORED.value,
                {
                    "prediction_id": str(
                        prediction.prediction_id
                    ),
                    "reason": (
                        "incoming prediction is older than "
                        "or equal to last evaluated prediction"
                    ),
                },
            )

            return

    # --------------------------------------------------------
    # NORMAL risk does not create an alert.
    # --------------------------------------------------------

    if incoming_band == Severity.NORMAL:

        logger.info(
            "prediction_id=%s has NORMAL severity; "
            "no alert created",
            prediction.prediction_id,
        )

        return

    # --------------------------------------------------------
    # Create a new alert with the incoming severity as a
    # candidate.
    # --------------------------------------------------------

    await _create_new_alert(
        prediction=prediction,
        incoming_band=incoming_band,
        incoming_key=incoming_key,
        session=session,
        alert_repo=alert_repo,
        audit_repo=audit_repo,
        config_repo=config_repo,
        notification_repo=notification_repo,
    )


# ============================================================
# EXISTING OPEN ALERT
# ============================================================

async def _evaluate_against_open_alert(
    alert: Alert,
    prediction: M5RiskPrediction,
    incoming_band: Severity,
    incoming_key,
    session: AsyncSession,
    alert_repo: AlertRepository,
    audit_repo: AuditRepository,
    config_repo: ConfigRepository,
    notification_repo: NotificationRepository,
) -> None:
    """
    Evaluate an incoming prediction against an existing
    non-terminal alert.
    """

    # --------------------------------------------------------
    # Ignore old/replayed predictions.
    # --------------------------------------------------------

    last_key = _composite_key(
        alert.last_evaluated_prediction_timestamp,
        alert.last_evaluated_created_at,
        alert.last_evaluated_prediction_id,
    )

    if (
        last_key[0] is not None
        and incoming_key <= last_key
    ):

        await audit_repo.add_entry(
            alert.alert_id,
            AuditEventType.DUPLICATE_EVENT_IGNORED.value,
            {
                "prediction_id": str(
                    prediction.prediction_id
                ),
                "reason": (
                    "incoming prediction is older than "
                    "or equal to last evaluated prediction"
                ),
            },
        )

        return

    # --------------------------------------------------------
    # Determine direction.
    # --------------------------------------------------------

    direction = classify_direction(
        alert.current_severity,
        incoming_band,
    )

    thresholds = None

    if direction is not None:

        thresholds = (
            await config_service.get_persistence_thresholds(
                config_repo,
                incoming_band,
                direction,
            )
        )

    # --------------------------------------------------------
    # Apply persistence rules.
    # --------------------------------------------------------

    result = evaluate_candidate(
        current_severity=alert.current_severity,
        candidate_severity=alert.candidate_severity,
        candidate_since=alert.candidate_since,
        candidate_confirmations=(
            alert.candidate_confirmations
        ),
        incoming_band=incoming_band,
        prediction_timestamp=(
            prediction.prediction_timestamp
        ),
        thresholds=thresholds,
    )

    # --------------------------------------------------------
    # Always update latest prediction information.
    # --------------------------------------------------------

    alert.last_evaluated_prediction_timestamp = (
        prediction.prediction_timestamp
    )

    alert.last_evaluated_created_at = (
        prediction.created_at
    )

    alert.last_evaluated_prediction_id = (
        prediction.prediction_id
    )

    alert.last_prediction_timestamp = (
        prediction.prediction_timestamp
    )

    alert.last_risk_score = (
        prediction.risk_score
    )

    alert.last_confidence = (
        prediction.confidence
    )

    # --------------------------------------------------------
    # Store current persistence candidate.
    # --------------------------------------------------------

    alert.candidate_severity = (
        result.candidate_severity
    )

    alert.candidate_since = (
        result.candidate_since
    )

    alert.candidate_confirmations = (
        result.candidate_confirmations
    )

    # --------------------------------------------------------
    # Persistence threshold reached.
    # --------------------------------------------------------

    if result.confirmed_severity is not None:

        outcome = apply_confirmed_transition(
            alert=alert,
            confirmed_severity=result.confirmed_severity,
            direction=result.direction,
            prediction_timestamp=(
                prediction.prediction_timestamp
            ),
        )

        await _record_transition_and_notify(
            alert=alert,
            outcome=outcome,
            audit_repo=audit_repo,
            config_repo=config_repo,
            notification_repo=notification_repo,
        )

    # --------------------------------------------------------
    # Candidate was reset because the incoming severity
    # changed direction/band before confirmation.
    # --------------------------------------------------------

    elif result.was_reset:

        await audit_repo.add_entry(
            alert.alert_id,
            AuditEventType.CANDIDATE_RESET.value,
            {
                "prediction_id": str(
                    prediction.prediction_id
                ),
                "incoming_band": incoming_band.value,
                "current_severity": (
                    alert.current_severity.value
                ),
            },
        )

    # --------------------------------------------------------
    # Persist alert changes.
    # --------------------------------------------------------

    await alert_repo.save(alert)


# ============================================================
# CREATE NEW ALERT
# ============================================================

async def _create_new_alert(
    prediction: M5RiskPrediction,
    incoming_band: Severity,
    incoming_key,
    session: AsyncSession,
    alert_repo: AlertRepository,
    audit_repo: AuditRepository,
    config_repo: ConfigRepository,
    notification_repo: NotificationRepository,
) -> None:
    """
    Create a new M5 alert.

    Important:

    M5 starts at NORMAL and stores the incoming severity as a
    candidate until persistence confirmation is reached.

    Therefore the legacy M3 severity must initially be LOW,
    because:

        M5 NORMAL -> M3 LOW

    We also populate M3's required title/message fields.
    """

    # --------------------------------------------------------
    # Get persistence thresholds for escalation.
    # --------------------------------------------------------

    thresholds = (
        await config_service.get_persistence_thresholds(
            config_repo,
            incoming_band,
            "escalate",
        )
    )

    # --------------------------------------------------------
    # Evaluate first candidate.
    # --------------------------------------------------------

    result = evaluate_candidate(
        current_severity=Severity.NORMAL,
        candidate_severity=None,
        candidate_since=None,
        candidate_confirmations=0,
        incoming_band=incoming_band,
        prediction_timestamp=(
            prediction.prediction_timestamp
        ),
        thresholds=thresholds,
    )

    # --------------------------------------------------------
    # M3 legacy fields.
    #
    # current M5 severity is NORMAL, therefore legacy M3
    # severity is LOW.
    # --------------------------------------------------------

    legacy_severity = severity_to_risk_level(
        Severity.NORMAL
    )

    title = (
        f"Landslide Risk Alert - "
        f"{incoming_band.value}"
    )

    message = (
        f"A {incoming_band.value} landslide-risk "
        f"condition was detected for area "
        f"{prediction.area_id}. "
        f"The condition is awaiting persistence "
        f"confirmation. "
        f"Risk score: {prediction.risk_score:.2f}."
    )

    # --------------------------------------------------------
    # Create alert.
    # --------------------------------------------------------

    fields = {
        # M3 legacy fields
        "risk_prediction_id": (
            prediction.prediction_id
        ),
        "severity": legacy_severity,
        "status": AlertStatus.ACTIVE,
        "title": title,
        "message": message,

        # M5 fields
        "area_id": prediction.area_id,
        "current_severity": Severity.NORMAL,
        "candidate_severity": (
            result.candidate_severity
        ),
        "candidate_since": (
            result.candidate_since
        ),
        "candidate_confirmations": (
            result.candidate_confirmations
        ),
        "lifecycle_status": (
            # Alert is active while persistence is being
            # evaluated.
            alert_lifecycle_active()
        ),

        "last_prediction_timestamp": (
            prediction.prediction_timestamp
        ),

        "last_evaluated_prediction_timestamp": (
            incoming_key[0]
        ),

        "last_evaluated_created_at": (
            incoming_key[1]
        ),

        "last_evaluated_prediction_id": (
            incoming_key[2]
        ),

        "last_risk_score": (
            prediction.risk_score
        ),

        "last_confidence": (
            prediction.confidence
        ),
    }

    alert = await alert_repo.create(
        **fields
    )

    # --------------------------------------------------------
    # Audit creation.
    # --------------------------------------------------------

    await audit_repo.add_entry(
        alert.alert_id,
        AuditEventType.ALERT_CREATED.value,
        {
            "prediction_id": str(
                prediction.prediction_id
            ),
            "initial_band": incoming_band.value,
            "current_severity": Severity.NORMAL.value,
            "candidate_severity": (
                result.candidate_severity.value
                if result.candidate_severity
                else None
            ),
            "risk_score": prediction.risk_score,
        },
    )

    # --------------------------------------------------------
    # If persistence was already satisfied on the first
    # observation, apply the confirmed transition.
    #
    # With the current defaults this normally does NOT happen,
    # because confirmations require 2 observations.
    # --------------------------------------------------------

    if result.confirmed_severity is not None:

        outcome = apply_confirmed_transition(
            alert=alert,
            confirmed_severity=(
                result.confirmed_severity
            ),
            direction=result.direction,
            prediction_timestamp=(
                prediction.prediction_timestamp
            ),
        )

        await _record_transition_and_notify(
            alert=alert,
            outcome=outcome,
            audit_repo=audit_repo,
            config_repo=config_repo,
            notification_repo=notification_repo,
        )

        await alert_repo.save(alert)


# ============================================================
# TRANSITION + NOTIFICATION
# ============================================================

async def _record_transition_and_notify(
    alert: Alert,
    outcome,
    audit_repo: AuditRepository,
    config_repo: ConfigRepository,
    notification_repo: NotificationRepository,
) -> None:
    """
    Record a confirmed transition and create a notification
    intent when appropriate.
    """

    # --------------------------------------------------------
    # Audit transition.
    # --------------------------------------------------------

    transition_details = {
        "direction": outcome.direction,
        "new_severity": (
            outcome.new_severity.value
            if outcome.new_severity is not None
            else None
        ),
        "lifecycle_changed": (
            outcome.lifecycle_changed
        ),
        "new_lifecycle": (
            outcome.new_lifecycle.value
            if outcome.new_lifecycle is not None
            else None
        ),
    }

    await audit_repo.add_entry(
        alert.alert_id,
        AuditEventType.SEVERITY_ESCALATION.value,
        transition_details,
    )

    # --------------------------------------------------------
    # Determine notification trigger.
    # --------------------------------------------------------

    if outcome.new_severity is None:
        return

    trigger_type = trigger_type_for_transition(
        outcome.direction,
        outcome.new_severity,
    )

    if trigger_type is None:
        return

    # --------------------------------------------------------
    # Downgrade notifications are configurable.
    # --------------------------------------------------------

    should_notify = True

    if outcome.direction == "downgrade":

        should_notify = (
            await config_service.get_notify_on_downgrade(
                config_repo
            )
        )

    if not should_notify:

        await audit_repo.add_entry(
            alert.alert_id,
            AuditEventType.NOTIFICATION_SKIPPED.value,
            {
                "reason": "downgrade_notifications_disabled",
                "trigger_type": trigger_type.value,
                "severity": (
                    outcome.new_severity.value
                ),
            },
        )

        return

    # --------------------------------------------------------
    # Create notification intent.
    # --------------------------------------------------------

    template_key = template_key_for(
        trigger_type,
        outcome.new_severity,
    )

    intent = await notification_repo.create_intent(
        alert_id=alert.alert_id,
        trigger_type=trigger_type,
        severity=outcome.new_severity,
        template_key=template_key,
        status=NotificationIntentStatus.PENDING,
    )

    # --------------------------------------------------------
    # Audit notification intent.
    # --------------------------------------------------------

    await audit_repo.add_entry(
        alert.alert_id,
        AuditEventType.NOTIFICATION_INTENT_CREATED.value,
        {
            "notification_trigger_id": str(
                intent.notification_trigger_id
            ),
            "trigger_type": trigger_type.value,
            "severity": (
                outcome.new_severity.value
            ),
            "template_key": template_key,
        },
    )


# ============================================================
# SMALL LOCAL HELPER
# ============================================================

def alert_lifecycle_active():
    """
    Return the M5 ACTIVE lifecycle enum.

    Kept as a helper so the alert creation section remains
    explicit about which lifecycle state is being assigned.
    """

    from app.core.enums import LifecycleStatus

    return LifecycleStatus.ACTIVE