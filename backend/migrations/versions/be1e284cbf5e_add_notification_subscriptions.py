"""add notification subscriptions

Revision ID: be1e284cbf5e
Revises: dcd5ce5c7a94
Create Date: 2026-09-24
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "be1e284cbf5e"
down_revision: Union[str, None] = "dcd5ce5c7a94"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "notification_subscriptions",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
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
            nullable=False,
        ),
        sa.Column(
            "destination",
            sa.String(length=255),
            nullable=False,
        ),
        sa.Column(
            "preferred_locale",
            sa.String(length=10),
            server_default="en",
            nullable=False,
        ),
        sa.Column(
            "priority",
            sa.Integer(),
            server_default="1",
            nullable=False,
        ),
        sa.Column(
            "is_active",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_index(
        "ix_notification_subscriptions_user_id",
        "notification_subscriptions",
        ["user_id"],
    )

    op.create_index(
        "ix_notification_subscriptions_is_active",
        "notification_subscriptions",
        ["is_active"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_notification_subscriptions_is_active",
        table_name="notification_subscriptions",
    )

    op.drop_index(
        "ix_notification_subscriptions_user_id",
        table_name="notification_subscriptions",
    )

    op.drop_table("notification_subscriptions")