"""
Add IoT sensor tables.

Revision ID: fffec405e6c5
Revises: be1e284cbf5e
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from geoalchemy2 import Geometry


revision: str = "fffec405e6c5"
down_revision: Union[str, Sequence[str], None] = "be1e284cbf5e"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create IoT sensor node and reading tables."""

    op.create_table(
        "iot_sensor_nodes",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("node_id", sa.String(length=100), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column(
            "location",
            Geometry(
                geometry_type="POINT",
                srid=4326,
                dimension=2,
                from_text="ST_GeomFromEWKT",
                name="geometry",
                nullable=False,
            ),
            nullable=False,
        ),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )

    # Spatial index for sensor-node locations.
    op.create_index(
        "idx_iot_nodes_location_gist",
        "iot_sensor_nodes",
        ["location"],
        unique=False,
        postgresql_using="gist",
        if_not_exists=True,
    )

    # Unique node identifier.
    op.create_index(
        "idx_iot_nodes_node_id_unique",
        "iot_sensor_nodes",
        ["node_id"],
        unique=True,
        if_not_exists=True,
    )

    op.create_table(
        "iot_sensor_readings",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("node_id", sa.UUID(), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("soil_moisture", sa.Float(), nullable=True),
        sa.Column("acceleration_x", sa.Float(), nullable=True),
        sa.Column("acceleration_y", sa.Float(), nullable=True),
        sa.Column("acceleration_z", sa.Float(), nullable=True),
        sa.Column("gyroscope_x", sa.Float(), nullable=True),
        sa.Column("gyroscope_y", sa.Float(), nullable=True),
        sa.Column("gyroscope_z", sa.Float(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["node_id"],
            ["iot_sensor_nodes.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )

    # Fast lookup of a node's readings by time.
    op.create_index(
        "idx_iot_readings_node_time",
        "iot_sensor_readings",
        ["node_id", "observed_at"],
        unique=False,
        if_not_exists=True,
    )

    op.create_index(
        "idx_iot_readings_node_id",
        "iot_sensor_readings",
        ["node_id"],
        unique=False,
        if_not_exists=True,
    )

    op.create_index(
        "idx_iot_readings_observed_at",
        "iot_sensor_readings",
        ["observed_at"],
        unique=False,
        if_not_exists=True,
    )


def downgrade() -> None:
    """Remove IoT sensor tables."""

    op.drop_index(
        "idx_iot_readings_observed_at",
        table_name="iot_sensor_readings",
    )

    op.drop_index(
        "idx_iot_readings_node_id",
        table_name="iot_sensor_readings",
    )

    op.drop_index(
        "idx_iot_readings_node_time",
        table_name="iot_sensor_readings",
    )

    op.drop_table("iot_sensor_readings")

    op.drop_index(
        "idx_iot_nodes_node_id_unique",
        table_name="iot_sensor_nodes",
    )

    op.drop_index(
        "idx_iot_nodes_location_gist",
        table_name="iot_sensor_nodes",
        postgresql_using="gist",
    )

    op.drop_table("iot_sensor_nodes")