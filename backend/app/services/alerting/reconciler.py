import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from app.core.database import AsyncSessionLocal
from app.core.enums import (
    AuditEventType,
    LifecycleStatus,
    NotificationIntentStatus,
    ProcessingStatus,
)
from app.core.exceptions import PredictionNotFoundError
from app.models.alert import Alert
from app.models.notification import NotificationIntent
from app.models.risk_prediction import RiskPrediction
from app.services.alerting.alert_repo import AlertRepository
from app.services.alerting.audit_repo import AuditRepository
from app.services.alerting.config_repo import ConfigRepository
from app.services.alerting.dispatcher import dispatch_pending_batch
from app.services.alerting.evaluator import (
    process_already_claimed_prediction,
    process_risk_event,
)
from app.services.alerting.notification_repo import NotificationRepository
from app.services.alerting.risk_event_repo import RiskEventRepository
from app.services.alerting.state_machine import apply_expiration, is_stale


logger = logging.getLogger(__name__)


# Lifecycle states that are still considered "open".
OPEN_LIFECYCLE_STATUSES = {
    LifecycleStatus.ACTIVE,
    LifecycleStatus.ACKNOWLEDGED,
}


async def reconcile_unprocessed_predictions() -> int:
    """
    Find predictions that either have no processed_risk_events row
    or are stuck in RETRYABLE status within the configured lookback
    window, and feed each through the same pipeline used by the
    normal risk-event processing flow.
    """

    async with AsyncSessionLocal() as session:
        config_repo = ConfigRepository(session)

        lookback_seconds = await config_repo.get_int(
            "reconciliation.lookback_seconds",
            default=1800,
        )

        since = datetime.now(timezone.utc) - timedelta(
            seconds=lookback_seconds
        )

        result = await session.execute(
            select(RiskPrediction.id).where(
                RiskPrediction.created_at >= since
            )
        )

        recent_ids = [row[0] for row in result.all()]

    processed = 0

    for prediction_id in recent_ids:
        async with AsyncSessionLocal() as session:
            risk_repo = RiskEventRepository(session)

            existing = await risk_repo.get_by_prediction_id(
                prediction_id
            )

            if existing is not None and existing.status in (
                ProcessingStatus.COMPLETED,
                ProcessingStatus.PROCESSING,
            ):
                # PROCESSING is handled separately by
                # reconcile_stale_processing().
                continue

            try:
                if (
                    existing is not None
                    and existing.status == ProcessingStatus.RETRYABLE
                ):
                    # Reclaim a retryable event before processing it.
                    won = await risk_repo.reclaim_retryable(
                        prediction_id
                    )

                    await session.commit()

                    if not won:
                        continue

                    await process_already_claimed_prediction(
                        prediction_id,
                        session,
                    )

                else:
                    await process_risk_event(
                        prediction_id,
                        session,
                    )

                processed += 1

            except PredictionNotFoundError:
                continue

            except Exception:
                logger.exception(
                    "reconciliation failed to process "
                    "prediction_id=%s",
                    prediction_id,
                )

    return processed


async def reconcile_stale_processing() -> int:
    """
    Recover predictions stuck in PROCESSING beyond the configured
    timeout, for example when a worker crashed after claiming the
    event but before completing processing.
    """

    async with AsyncSessionLocal() as session:
        config_repo = ConfigRepository(session)

        timeout_seconds = await config_repo.get_int(
            "reconciliation.stale_processing_timeout_seconds",
            default=120,
        )

        stale_before = datetime.now(timezone.utc) - timedelta(
            seconds=timeout_seconds
        )

        risk_repo = RiskEventRepository(session)

        stale = await risk_repo.list_stale_processing(
            stale_before
        )

        stale_ids = [
            row.prediction_id
            for row in stale
        ]

    reclaimed = 0

    for prediction_id in stale_ids:
        async with AsyncSessionLocal() as session:
            risk_repo = RiskEventRepository(session)

            config_repo = ConfigRepository(session)

            timeout_seconds = await config_repo.get_int(
                "reconciliation.stale_processing_timeout_seconds",
                default=120,
            )

            stale_before = datetime.now(timezone.utc) - timedelta(
                seconds=timeout_seconds
            )

            won = await risk_repo.reclaim_stale(
                prediction_id,
                stale_before,
            )

            await session.commit()

            if not won:
                continue

            try:
                # The row has already been reclaimed, so do not call
                # process_risk_event(), which would attempt another claim.
                await process_already_claimed_prediction(
                    prediction_id,
                    session,
                )

                reclaimed += 1

            except PredictionNotFoundError:
                continue

            except Exception:
                logger.exception(
                    "reconciliation failed to reprocess "
                    "stale prediction_id=%s",
                    prediction_id,
                )

    return reclaimed


async def reconcile_notifications(
    batch_size: int | None = None,
) -> int:
    """
    Recover pending notification intents, incomplete deliveries,
    and retryable notification failures.
    """

    await _requeue_transient_failed_intents()

    return await dispatch_pending_batch(
        batch_size=batch_size
    )


async def _requeue_transient_failed_intents() -> int:
    """
    Requeue notification intents that have transient delivery
    failures and are still within the configured retry limit.
    """

    async with AsyncSessionLocal() as session:
        config_repo = ConfigRepository(session)
        notif_repo = NotificationRepository(session)

        max_retries = await config_repo.get_int(
            "dispatch.max_retries",
            default=3,
        )

        intent_ids = await notif_repo.list_transient_failed_intent_ids(
            max_retries
        )

        requeued = 0

        for intent_id in intent_ids:
            result = await session.execute(
                update(NotificationIntent)
                .where(
                    NotificationIntent.notification_trigger_id
                    == intent_id,
                    NotificationIntent.status
                    == NotificationIntentStatus.DISPATCHED,
                )
                .values(
                    status=NotificationIntentStatus.PENDING
                )
                .returning(
                    NotificationIntent.notification_trigger_id
                )
            )

            if result.first() is not None:
                requeued += 1

        await session.commit()

        if requeued:
            logger.info(
                "requeued %s intent(s) with retry-eligible "
                "transient delivery failures",
                requeued,
            )

        return requeued


async def reconcile_stale_areas() -> int:
    """
    Detect alert areas whose prediction stream has gone silent
    beyond the configured maximum prediction gap and expire
    those alerts.

    Missing prediction data is not interpreted as NORMAL/safe.
    """

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Alert).where(
                Alert.lifecycle_status.in_(
                    list(OPEN_LIFECYCLE_STATUSES)
                )
            )
        )

        open_alerts = result.scalars().all()

        open_alert_ids = [
            alert.id
            for alert in open_alerts
        ]

    expired = 0

    for alert_id in open_alert_ids:
        async with AsyncSessionLocal() as session:
            alert_repo = AlertRepository(session)
            audit_repo = AuditRepository(session)
            config_repo = ConfigRepository(session)

            alert = await alert_repo.get_by_id(alert_id)

            if (
                alert is None
                or alert.lifecycle_status
                not in OPEN_LIFECYCLE_STATUSES
            ):
                continue

            await alert_repo.acquire_area_lock(
                alert.area_id
            )

            # Re-read the alert after acquiring the lock.
            alert = await alert_repo.get_by_id(alert_id)

            if (
                alert is None
                or alert.lifecycle_status
                not in OPEN_LIFECYCLE_STATUSES
            ):
                await session.rollback()
                continue

            max_gap = await config_repo.get_int(
                "max_prediction_gap_seconds",
                default=3600,
            )

            now = datetime.now(timezone.utc)

            if is_stale(
                alert,
                now,
                max_gap,
            ):
                apply_expiration(
                    alert,
                    now,
                )

                await alert_repo.save(alert)

                await audit_repo.add_entry(
                    alert.id,
                    AuditEventType.LIFECYCLE_EXPIRED.value,
                    {
                        "reason": "max_prediction_gap_exceeded",
                        "max_gap_seconds": max_gap,
                    },
                )

                await session.commit()

                expired += 1

            else:
                await session.rollback()

    return expired


async def run_reconciliation_cycle() -> dict:
    """
    Run all reconciliation duties once.

    Returns a summary dictionary for logging and observability.
    """

    summary = {}

    try:
        summary[
            "predictions_reconciled"
        ] = await reconcile_unprocessed_predictions()

    except Exception:
        logger.exception(
            "reconcile_unprocessed_predictions failed"
        )

        summary[
            "predictions_reconciled"
        ] = -1

    try:
        summary[
            "stale_processing_reclaimed"
        ] = await reconcile_stale_processing()

    except Exception:
        logger.exception(
            "reconcile_stale_processing failed"
        )

        summary[
            "stale_processing_reclaimed"
        ] = -1

    try:
        summary[
            "notification_intents_dispatched"
        ] = await reconcile_notifications()

    except Exception:
        logger.exception(
            "reconcile_notifications failed"
        )

        summary[
            "notification_intents_dispatched"
        ] = -1

    try:
        summary[
            "areas_expired"
        ] = await reconcile_stale_areas()

    except Exception:
        logger.exception(
            "reconcile_stale_areas failed"
        )

        summary[
            "areas_expired"
        ] = -1

    logger.info(
        "reconciliation cycle complete: %s",
        summary,
    )

    return summary

class AlertReconciler:
    """
    Compatibility wrapper for the M5 reconciliation service.

    The actual reconciliation logic is implemented by the
    module-level async functions above.
    """

    async def reconcile_unprocessed_predictions(self) -> int:
        return await reconcile_unprocessed_predictions()

    async def reconcile_stale_processing(self) -> int:
        return await reconcile_stale_processing()

    async def reconcile_notifications(
        self,
        batch_size: int | None = None,
    ) -> int:
        return await reconcile_notifications(
            batch_size=batch_size
        )

    async def reconcile_stale_areas(self) -> int:
        return await reconcile_stale_areas()

    async def run_cycle(self) -> dict:
        return await run_reconciliation_cycle()