from app.core.enums import Severity, TriggerType


def trigger_type_for_transition(
    direction: str | None,
    severity: Severity,
) -> TriggerType | None:
    """
    Determine the notification trigger for a confirmed
    severity transition.
    """

    if direction == "escalate":

        if severity == Severity.WATCH:
            return TriggerType.WATCH_ESCALATION

        if severity == Severity.WARNING:
            return TriggerType.WARNING_ESCALATION

        if severity == Severity.CRITICAL:
            return TriggerType.CRITICAL_ESCALATION

    elif direction == "resolve":

        return TriggerType.RESOLUTION

    elif direction == "downgrade":

        return TriggerType.DOWNGRADE_NOTICE

    return None


def template_key_for(
    trigger_type: TriggerType,
    severity: Severity,
) -> str:
    """
    Return the exact key used by notification_templates.py.
    """

    if trigger_type == TriggerType.WATCH_ESCALATION:
        return "watch_escalation.watch"

    if trigger_type == TriggerType.WARNING_ESCALATION:
        return "warning_escalation.warning"

    if trigger_type == TriggerType.CRITICAL_ESCALATION:
        return "critical_escalation.critical"

    if trigger_type == TriggerType.RESOLUTION:
        return "resolution.normal"

    if trigger_type == TriggerType.DOWNGRADE_NOTICE:

        if severity == Severity.WATCH:
            return "downgrade_notice.watch"

        if severity == Severity.WARNING:
            return "downgrade_notice.warning"

        # A downgrade from CRITICAL should normally land in
        # WARNING or WATCH, so this is a defensive fallback.
        if severity == Severity.CRITICAL:
            return "downgrade_notice.warning"

    raise ValueError(
        f"No notification template for "
        f"trigger_type={trigger_type}, severity={severity}"
    )