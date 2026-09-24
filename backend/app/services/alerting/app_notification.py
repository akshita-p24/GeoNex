"""
Backend-only APP notification provider for M5 demo/testing.

This provider does not contact an external service.
It simply records a successful notification so the complete
M5 alert -> recipient -> delivery pipeline can be demonstrated.
"""

from typing import Any

from app.services.alerting.notification_base import NotificationProvider


class AppNotificationProvider(NotificationProvider):
    """
    Mock/in-app notification provider.

    For the SIH demo this represents a notification delivered
    to the GeoNex application itself.
    """

    async def send(
        self,
        destination: str,
        message: str,
    ) -> dict[str, Any]:
        print()
        print("======================================")
        print("M5 APP NOTIFICATION")
        print("======================================")
        print(f"Recipient : {destination}")
        print(f"Message   : {message}")
        print("Status    : DELIVERED")
        print("======================================")
        print()

        return {
            "provider_message_id": f"APP-DEMO-{destination}",
        }