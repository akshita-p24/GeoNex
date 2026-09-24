import asyncio
import logging
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.enums import (
    DeliveryChannel,
    DeliveryStatus,
    FailureType,
    NotificationIntentStatus,
)
from app.models.alert import AlertDelivery
from app.services.alerting.alert_repo import AlertRepository
from app.services.alerting.config_repo import ConfigRepository
from app.services.alerting.cooldown_repo import CooldownRepository
from app.services.alerting.fcm import FCMProvider
from app.services.alerting.m3_client import resolve_recipients
from app.services.alerting.notification_base import (
    NotificationProvider,
    ProviderError,
)
from app.services.alerting.notification_repo import NotificationRepository
from app.services.alerting.notification_templates import render_message
from app.services.alerting.twilio import TwilioProvider
from app.services.alerting.app_notification import (
    AppNotificationProvider,
)


logger = logging.getLogger(__name__)

settings = get_settings()

_dispatcher_task: "asyncio.Task | None" = None


_PROVIDERS: Dict[DeliveryChannel, NotificationProvider] = {
    DeliveryChannel.SMS: TwilioProvider(),
    DeliveryChannel.PUSH: FCMProvider(),
    DeliveryChannel.APP: AppNotificationProvider(),
}

def _now() -> datetime:
    return datetime.now(timezone.utc)


async def _process_one_intent(
    session: AsyncSession,
    intent_id,
) -> None:

    notif_repo = NotificationRepository(session)
    alert_repo = AlertRepository(session)
    config_repo = ConfigRepository(session)
    cooldown_repo = CooldownRepository(session)

    intent = await notif_repo.get_intent_by_id(intent_id)

    if intent is None:
        return

    alert = await alert_repo.get_by_id(intent.alert_id)

    if alert is None:
        logger.error(
            "alert %s not found for intent %s",
            intent.alert_id,
            intent.notification_trigger_id,
        )

        await notif_repo.set_intent_status(
            intent.notification_trigger_id,
            NotificationIntentStatus.FAILED,
        )

        await session.commit()
        return

    # ---------------------------------------------------------
    # Phase 1: resolve recipients through M3
    # ---------------------------------------------------------

    try:
        recipients: List[Dict[str, Any]] = await resolve_recipients(
            area_id=alert.area_id,
            alert_id=str(intent.alert_id),
            severity=alert.current_severity.value,
        )

    except Exception:
        logger.exception(
            "M3 recipient resolution failed for intent %s",
            intent.notification_trigger_id,
        )

        await notif_repo.set_intent_status(
            intent.notification_trigger_id,
            NotificationIntentStatus.PENDING,
        )

        await session.commit()
        return

    # ---------------------------------------------------------
    # Phase 2: cooldown + delivery creation
    # ---------------------------------------------------------

    to_attempt = []

    for recipient in recipients:

        recipient_id = recipient.get("recipient_id")

        channel_strs = recipient.get("preferred_channels") or (
            [recipient["channel"]]
            if recipient.get("channel")
            else []
        )

        for channel_str in channel_strs:

            channel_str = (channel_str or "").upper()

            try:
                channel = DeliveryChannel(channel_str)

            except ValueError:
                logger.warning(
                    "unknown channel '%s' for recipient %s",
                    channel_str,
                    recipient_id,
                )
                continue

            # -------------------------------------------------
            # Check channel + trigger-specific cooldown
            # -------------------------------------------------

            cooldown_active = await cooldown_repo.is_active(
                intent.alert_id,
                channel,
                intent.trigger_type.value,
                _now(),
            )

            if cooldown_active:
                logger.info(
                    "notification suppressed by cooldown "
                    "alert=%s channel=%s trigger=%s",
                    intent.alert_id,
                    channel.value,
                    intent.trigger_type.value,
                )
                continue

            # -------------------------------------------------
            # Create or reuse pending delivery
            # -------------------------------------------------

            delivery, created = (
                await notif_repo.get_or_create_pending_delivery(
                    alert_id=intent.alert_id,
                    notification_trigger_id=(
                        intent.notification_trigger_id
                    ),
                    recipient_id=recipient_id,
                    channel=channel,
                    status=DeliveryStatus.PENDING,
                )
            )

            if delivery.status in (
                DeliveryStatus.SENT,
                DeliveryStatus.DELIVERED,
            ):
                continue

            if (
                delivery.status == DeliveryStatus.FAILED
                and delivery.error_type == FailureType.PERMANENT
            ):
                continue

            to_attempt.append(
                (
                    delivery.delivery_id,
                    channel,
                    recipient,
                )
            )

    await session.commit()

    # ---------------------------------------------------------
    # Phase 3: render notification message
    # ---------------------------------------------------------

    message = render_message(
        intent.template_key,
        locale="en",
        facts={
            "area_id": alert.area_id,
            "severity": alert.current_severity.value,
        },
    )

    # ---------------------------------------------------------
    # Phase 4: external provider sends
    # ---------------------------------------------------------

    results = []

    for delivery_id, channel, recipient in to_attempt:

        provider = _PROVIDERS.get(channel)

        if provider is None:

            results.append(
                (
                    delivery_id,
                    channel,
                    False,
                    ProviderError(
                        "no provider for channel",
                        FailureType.PERMANENT,
                    ),
                )
            )

            continue

        if channel == DeliveryChannel.SMS:
            destination = recipient.get("phone_number")

        elif channel == DeliveryChannel.PUSH:
            destination = recipient.get("device_token")

        elif channel == DeliveryChannel.APP:
            destination = recipient.get("recipient_id")

        else:
            destination = None

        if not destination:

            results.append(
                (
                    delivery_id,
                    channel,
                    False,
                    ProviderError(
                        (
                            f"no {channel.value} destination "
                            "on file for recipient"
                        ),
                        FailureType.PERMANENT,
                    ),
                )
            )

            continue

        try:

            payload = await provider.send(
                destination,
                message,
            )

            results.append(
                (
                    delivery_id,
                    channel,
                    True,
                    payload,
                )
            )

        except ProviderError as exc:

            results.append(
                (
                    delivery_id,
                    channel,
                    False,
                    exc,
                )
            )

        except Exception as exc:

            logger.exception(
                "unexpected provider error"
            )

            results.append(
                (
                    delivery_id,
                    channel,
                    False,
                    ProviderError(
                        str(exc),
                        FailureType.TRANSIENT,
                    ),
                )
            )

    # ---------------------------------------------------------
    # Phase 5: record results + cooldowns
    # ---------------------------------------------------------

    max_retries = await config_repo.get_int(
        "dispatch.max_retries",
        default=3,
    )

    for delivery_id, channel, ok, payload in results:

        if ok:

            await notif_repo.update_delivery_status(
                delivery_id,
                DeliveryStatus.SENT,
                provider_message_id=payload.get(
                    "provider_message_id"
                ),
                attempt_count=(
                    AlertDelivery.attempt_count + 1
                ),
                last_attempt_at=_now(),
                sent_at=_now(),
            )

            # ---------------------------------------------
            # FIXED:
            # Use channel + trigger-specific cooldown
            # ---------------------------------------------

            cooldown_key = (
                f"cooldown."
                f"{channel.value}."
                f"{intent.trigger_type.value}."
                f"seconds"
            )

            cooldown_seconds = await config_repo.get_int(
                cooldown_key,
                default=0,
            )

            if cooldown_seconds > 0:

                cooldown_until = (
                    _now()
                    + timedelta(seconds=cooldown_seconds)
                )

                await cooldown_repo.set_cooldown(
                    intent.alert_id,
                    channel,
                    intent.trigger_type.value,
                    cooldown_until,
                )

                logger.info(
                    "cooldown set: alert=%s channel=%s "
                    "trigger=%s seconds=%s",
                    intent.alert_id,
                    channel.value,
                    intent.trigger_type.value,
                    cooldown_seconds,
                )

        else:

            exc: ProviderError = payload

            delivery = await notif_repo.get_delivery_by_id(
                delivery_id
            )

            attempt_count = (
                delivery.attempt_count
                if delivery
                else 0
            ) + 1

            final = (
                exc.failure_type == FailureType.PERMANENT
                or attempt_count >= max_retries
            )

            await notif_repo.update_delivery_status(
                delivery_id,
                DeliveryStatus.FAILED,
                error_type=exc.failure_type,
                error_message=str(exc)[:2000],
                attempt_count=attempt_count,
                last_attempt_at=_now(),
            )

            if not final:

                logger.info(
                    "delivery %s transient failure, "
                    "attempt %s/%s, will retry",
                    delivery_id,
                    attempt_count,
                    max_retries,
                )

    # ---------------------------------------------------------
    # Phase 6: mark intent dispatched
    # ---------------------------------------------------------

    await notif_repo.set_intent_status(
        intent.notification_trigger_id,
        NotificationIntentStatus.DISPATCHED,
    )

    await session.commit()


async def dispatch_pending_batch(
    batch_size: int | None = None,
) -> int:
    """
    Claim and process pending notification intents.
    """

    # ---------------------------------------------------------
    # FIXED:
    # Your actual database session factory is AsyncSessionLocal
    # ---------------------------------------------------------

    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as session:

        config_repo = ConfigRepository(session)

        if batch_size is None:

            batch_size = await config_repo.get_int(
                "dispatch.batch_size",
                default=100,
            )

        notif_repo = NotificationRepository(session)

        intents = await notif_repo.claim_pending_batch(
            batch_size
        )

        await session.commit()

        processed = 0

        for intent in intents:

            try:

                await _process_one_intent(
                    session,
                    intent.notification_trigger_id,
                )

            except Exception:

                logger.exception(
                    "failed processing intent %s",
                    intent.notification_trigger_id,
                )

                await session.rollback()

                await notif_repo.set_intent_status(
                    intent.notification_trigger_id,
                    NotificationIntentStatus.PENDING,
                )

                await session.commit()

            processed += 1

        batch_delay = await config_repo.get_float(
            "dispatch.batch_delay_seconds",
            default=1.0,
        )

        if processed and batch_delay:

            await asyncio.sleep(batch_delay)

        return processed


async def _dispatch_loop() -> None:

    interval = getattr(
        settings,
        "DISPATCH_LOOP_INTERVAL_SECONDS",
        10,
    )

    logger.info(
        "Notification dispatcher loop started, interval=%ss",
        interval,
    )

    while True:

        try:

            await dispatch_pending_batch()

        except Exception:

            logger.exception(
                "Unexpected error in dispatcher loop"
            )

        await asyncio.sleep(interval)


async def start_dispatcher() -> None:

    global _dispatcher_task

    enabled = getattr(
        settings,
        "ENABLE_DISPATCHER",
        False,
    )

    if not enabled:

        logger.info(
            "M5 dispatcher is disabled "
            "(ENABLE_DISPATCHER=False)"
        )

        return

    if (
        _dispatcher_task is None
        or _dispatcher_task.done()
    ):

        _dispatcher_task = asyncio.create_task(
            _dispatch_loop()
        )

        logger.info(
            "M5 dispatcher task started"
        )


async def stop_dispatcher() -> None:

    global _dispatcher_task

    if (
        _dispatcher_task
        and not _dispatcher_task.done()
    ):

        _dispatcher_task.cancel()

        try:

            await _dispatcher_task

        except asyncio.CancelledError:

            logger.info(
                "M5 dispatcher task cancelled"
            )

        _dispatcher_task = None