"""integrate m5 alert engine

Revision ID: dcd5ce5c7a94
Revises: 4fe6838daedc
Create Date: 2026-09-23 14:53:30.447680
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "dcd5ce5c7a94"
down_revision: Union[str, Sequence[str], None] = "4fe6838daedc"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ---------------------------------------------------------
    # 1. Add SENDING to the existing M3 delivery_status enum
    # ---------------------------------------------------------
    op.execute(
        "ALTER TYPE delivery_status ADD VALUE IF NOT EXISTS 'SENDING'"
    )

    # ---------------------------------------------------------
    # 2. Add CANCELLED to the existing M3 alert_status enum
    # ---------------------------------------------------------
    op.execute(
        "ALTER TYPE alert_status ADD VALUE IF NOT EXISTS 'CANCELLED'"
    )

    # ---------------------------------------------------------
    # 3. M5 severity enum
    #    LOW -> NORMAL
    #    MODERATE -> WATCH
    #    HIGH -> WARNING
    #    VERY HIGH -> CRITICAL
    # ---------------------------------------------------------
    severity_enum = postgresql.ENUM(
        "NORMAL",
        "WATCH",
        "WARNING",
        "CRITICAL",
        name="severity",
    )
    severity_enum.create(op.get_bind(), checkfirst=True)

    # ---------------------------------------------------------
    # 4. M5 lifecycle status enum
    # ---------------------------------------------------------
    lifecycle_status_enum = postgresql.ENUM(
        "ACTIVE",
        "ACKNOWLEDGED",
        "RESOLVED",
        "CANCELLED",
        "EXPIRED",
        name="lifecycle_status",
    )
    lifecycle_status_enum.create(op.get_bind(), checkfirst=True)

    # ---------------------------------------------------------
    # 5. M5 trigger type enum
    # ---------------------------------------------------------
    trigger_type_enum = postgresql.ENUM(
        "WATCH_ESCALATION",
        "WARNING_ESCALATION",
        "CRITICAL_ESCALATION",
        "RESOLUTION",
        "DOWNGRADE_NOTICE",
        name="trigger_type",
    )
    trigger_type_enum.create(op.get_bind(), checkfirst=True)

    # ---------------------------------------------------------
    # 6. Notification intent status
    # ---------------------------------------------------------
    notification_intent_status_enum = postgresql.ENUM(
        "PENDING",
        "DISPATCHING",
        "DISPATCHED",
        "FAILED",
        name="notification_intent_status",
    )
    notification_intent_status_enum.create(
        op.get_bind(), checkfirst=True
    )

    # ---------------------------------------------------------
    # 7. Failure type
    # ---------------------------------------------------------
    failure_type_enum = postgresql.ENUM(
        "TRANSIENT",
        "PERMANENT",
        name="failure_type",
    )
    failure_type_enum.create(op.get_bind(), checkfirst=True)

    # ---------------------------------------------------------
    # 8. Processing status
    # ---------------------------------------------------------
    processing_status_enum = postgresql.ENUM(
        "RECEIVED",
        "PROCESSING",
        "COMPLETED",
        "RETRYABLE",
        "FAILED",
        name="processing_status",
    )
    processing_status_enum.create(op.get_bind(), checkfirst=True)

    # ---------------------------------------------------------
    # 9. Add M5 state fields to existing alerts table
    # ---------------------------------------------------------

    op.add_column(
        "alerts",
        sa.Column("area_id", sa.String(), nullable=True),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "current_severity",
            postgresql.ENUM(
                "NORMAL",
                "WATCH",
                "WARNING",
                "CRITICAL",
                name="severity",
                create_type=False,
            ),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "candidate_severity",
            postgresql.ENUM(
                "NORMAL",
                "WATCH",
                "WARNING",
                "CRITICAL",
                name="severity",
                create_type=False,
            ),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "candidate_since",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "candidate_confirmations",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "lifecycle_status",
            postgresql.ENUM(
                "ACTIVE",
                "ACKNOWLEDGED",
                "RESOLVED",
                "CANCELLED",
                "EXPIRED",
                name="lifecycle_status",
                create_type=False,
            ),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "band_entered_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "last_prediction_timestamp",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "last_evaluated_prediction_timestamp",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "last_evaluated_created_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "last_evaluated_prediction_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "last_risk_score",
            sa.Float(),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "last_confidence",
            sa.Float(),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "resolved_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "cancelled_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alerts",
        sa.Column(
            "expired_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    # Existing M3 alerts, if any, are mapped into M5 state.
    op.execute(
        """
        UPDATE alerts
        SET
            current_severity =
                CASE severity::text
                    WHEN 'LOW' THEN 'NORMAL'::severity
                    WHEN 'WATCH' THEN 'WATCH'::severity
                    WHEN 'WARNING' THEN 'WARNING'::severity
                    WHEN 'CRITICAL' THEN 'CRITICAL'::severity
                END,
            lifecycle_status =
                CASE status::text
                    WHEN 'ACTIVE' THEN 'ACTIVE'::lifecycle_status
                    WHEN 'ACKNOWLEDGED' THEN 'ACKNOWLEDGED'::lifecycle_status
                    WHEN 'RESOLVED' THEN 'RESOLVED'::lifecycle_status
                    WHEN 'EXPIRED' THEN 'EXPIRED'::lifecycle_status
                    WHEN 'CANCELLED' THEN 'CANCELLED'::lifecycle_status
                END,
            updated_at = COALESCE(created_at, now())
        """
    )

    # Safe defaults for any existing records.
    op.execute(
        """
        UPDATE alerts
        SET current_severity = 'NORMAL'::severity
        WHERE current_severity IS NULL
        """
    )

    op.execute(
        """
        UPDATE alerts
        SET lifecycle_status = 'ACTIVE'::lifecycle_status
        WHERE lifecycle_status IS NULL
        """
    )

    op.alter_column(
        "alerts",
        "current_severity",
        nullable=False,
    )

    op.alter_column(
        "alerts",
        "lifecycle_status",
        nullable=False,
    )

    op.alter_column(
        "alerts",
        "updated_at",
        nullable=False,
    )

    # ---------------------------------------------------------
    # 10. Active alert uniqueness per area
    # ---------------------------------------------------------
    op.create_index(
        "uq_alerts_area_active",
        "alerts",
        ["area_id"],
        unique=True,
        postgresql_where=sa.text(
            "lifecycle_status IN ('ACTIVE', 'ACKNOWLEDGED')"
        ),
    )

    op.create_index(
        "ix_alerts_area_id_updated_at",
        "alerts",
        ["area_id", "updated_at"],
    )

    # ---------------------------------------------------------
    # 11. M5 notification_intents
    # ---------------------------------------------------------
    op.create_table(
        "notification_intents",
        sa.Column(
            "notification_trigger_id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "alert_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("alerts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "trigger_type",
            postgresql.ENUM(
                "WATCH_ESCALATION",
                "WARNING_ESCALATION",
                "CRITICAL_ESCALATION",
                "RESOLUTION",
                "DOWNGRADE_NOTICE",
                name="trigger_type",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column(
            "severity",
            postgresql.ENUM(
                "NORMAL",
                "WATCH",
                "WARNING",
                "CRITICAL",
                name="severity",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column(
            "template_key",
            sa.String(),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "status",
            postgresql.ENUM(
                "PENDING",
                "DISPATCHING",
                "DISPATCHED",
                "FAILED",
                name="notification_intent_status",
                create_type=False,
            ),
            nullable=False,
            server_default="PENDING",
        ),
    )

    op.create_index(
        "ix_notification_intents_status",
        "notification_intents",
        ["status"],
    )

    op.create_index(
        "ix_notification_intents_alert_id",
        "notification_intents",
        ["alert_id"],
    )

    # ---------------------------------------------------------
    # 12. Extend existing alert_deliveries for M5
    # ---------------------------------------------------------
    op.add_column(
        "alert_deliveries",
        sa.Column(
            "notification_trigger_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alert_deliveries",
        sa.Column(
            "provider_message_id",
            sa.String(),
            nullable=True,
        ),
    )

    op.add_column(
        "alert_deliveries",
        sa.Column(
            "attempt_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    op.add_column(
        "alert_deliveries",
        sa.Column(
            "last_attempt_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alert_deliveries",
        sa.Column(
            "delivered_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    op.add_column(
        "alert_deliveries",
        sa.Column(
            "error_type",
            postgresql.ENUM(
                "TRANSIENT",
                "PERMANENT",
                name="failure_type",
                create_type=False,
            ),
            nullable=True,
        ),
    )

    op.add_column(
        "alert_deliveries",
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
    )

    op.create_foreign_key(
        "fk_alert_deliveries_notification_intent",
        "alert_deliveries",
        "notification_intents",
        ["notification_trigger_id"],
        ["notification_trigger_id"],
        ondelete="CASCADE",
    )

    op.create_unique_constraint(
        "uq_alert_delivery_intent_recipient_channel",
        "alert_deliveries",
        [
            "alert_id",
            "recipient",
            "channel",
            "notification_trigger_id",
        ],
    )

    # ---------------------------------------------------------
    # 13. processed_risk_events
    # ---------------------------------------------------------
    op.create_table(
        "processed_risk_events",
        sa.Column(
            "prediction_id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
        ),
        sa.Column(
            "area_id",
            sa.String(),
            nullable=True,
        ),
        sa.Column(
            "prediction_timestamp",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column(
            "status",
            postgresql.ENUM(
                "RECEIVED",
                "PROCESSING",
                "COMPLETED",
                "RETRYABLE",
                "FAILED",
                name="processing_status",
                create_type=False,
            ),
            nullable=False,
            server_default="RECEIVED",
        ),
        sa.Column(
            "received_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "processing_started_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column(
            "completed_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column(
            "retry_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "last_error",
            sa.Text(),
            nullable=True,
        ),
    )

    op.create_index(
        "ix_processed_risk_events_status",
        "processed_risk_events",
        ["status"],
    )

    op.create_index(
        "ix_processed_risk_events_area_id",
        "processed_risk_events",
        ["area_id"],
    )

    # ---------------------------------------------------------
    # 14. alert_config
    # ---------------------------------------------------------
    op.create_table(
        "alert_config",
        sa.Column(
            "config_key",
            sa.String(),
            primary_key=True,
        ),
        sa.Column(
            "config_value",
            sa.String(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_by",
            sa.String(),
            nullable=True,
        ),
    )

    # ---------------------------------------------------------
    # 15. notification_cooldowns
    # ---------------------------------------------------------
    op.create_table(
        "notification_cooldowns",
        sa.Column(
            "alert_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("alerts.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "channel",
            postgresql.ENUM(
                "SMS",
                "PUSH",
                "APP",
                "EMAIL",
                name="delivery_channel",
                create_type=False,
            ),
            primary_key=True,
        ),
        sa.Column(
            "trigger_type",
            sa.String(),
            primary_key=True,
        ),
        sa.Column(
            "cooldown_until",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
    )

    # ---------------------------------------------------------
    # 16. alert_audit_log
    # ---------------------------------------------------------
    op.create_table(
        "alert_audit_log",
        sa.Column(
            "audit_id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "alert_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("alerts.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "event_type",
            sa.String(),
            nullable=False,
        ),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "event_metadata",
            postgresql.JSONB(),
            nullable=True,
        ),
    )

    op.create_index(
        "ix_alert_audit_log_alert_id",
        "alert_audit_log",
        ["alert_id"],
    )


def downgrade() -> None:
    # Remove M5 tables first.
    op.drop_index(
        "ix_alert_audit_log_alert_id",
        table_name="alert_audit_log",
    )
    op.drop_table("alert_audit_log")

    op.drop_table("notification_cooldowns")

    op.drop_table("alert_config")

    op.drop_index(
        "ix_processed_risk_events_area_id",
        table_name="processed_risk_events",
    )
    op.drop_index(
        "ix_processed_risk_events_status",
        table_name="processed_risk_events",
    )
    op.drop_table("processed_risk_events")

    op.drop_constraint(
        "uq_alert_delivery_intent_recipient_channel",
        "alert_deliveries",
        type_="unique",
    )

    op.drop_constraint(
        "fk_alert_deliveries_notification_intent",
        "alert_deliveries",
        type_="foreignkey",
    )

    op.drop_column("alert_deliveries", "updated_at")
    op.drop_column("alert_deliveries", "error_type")
    op.drop_column("alert_deliveries", "delivered_at")
    op.drop_column("alert_deliveries", "last_attempt_at")
    op.drop_column("alert_deliveries", "attempt_count")
    op.drop_column("alert_deliveries", "provider_message_id")
    op.drop_column("alert_deliveries", "notification_trigger_id")

    op.drop_index(
        "ix_notification_intents_alert_id",
        table_name="notification_intents",
    )
    op.drop_index(
        "ix_notification_intents_status",
        table_name="notification_intents",
    )
    op.drop_table("notification_intents")

    op.drop_index(
        "ix_alerts_area_id_updated_at",
        table_name="alerts",
    )
    op.drop_index(
        "uq_alerts_area_active",
        table_name="alerts",
    )

    op.drop_column("alerts", "expired_at")
    op.drop_column("alerts", "cancelled_at")
    op.drop_column("alerts", "resolved_at")
    op.drop_column("alerts", "updated_at")
    op.drop_column("alerts", "last_confidence")
    op.drop_column("alerts", "last_risk_score")
    op.drop_column("alerts", "last_evaluated_prediction_id")
    op.drop_column("alerts", "last_evaluated_created_at")
    op.drop_column("alerts", "last_evaluated_prediction_timestamp")
    op.drop_column("alerts", "last_prediction_timestamp")
    op.drop_column("alerts", "band_entered_at")
    op.drop_column("alerts", "lifecycle_status")
    op.drop_column("alerts", "candidate_confirmations")
    op.drop_column("alerts", "candidate_since")
    op.drop_column("alerts", "candidate_severity")
    op.drop_column("alerts", "current_severity")
    op.drop_column("alerts", "area_id")

    # PostgreSQL enum values cannot be safely removed with simple
    # ALTER TYPE statements. They are therefore intentionally retained
    # during downgrade.