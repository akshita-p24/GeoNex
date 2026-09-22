"""
app/models/spatial.py

SQLAlchemy models for geographic reference layers:
- Roads (LINESTRING geometry, e.g., NH-44, Border roads in NER)
- Villages / Settlements (POINT geometry)
- Infrastructure / Critical Assets (POINT geometry, e.g., Hospitals, Bridges, Schools)
"""

import uuid
from datetime import datetime
from enum import Enum as PyEnum

from geoalchemy2 import Geometry
from sqlalchemy import String, Integer, Float, DateTime, Enum, func, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class InfrastructureCategory(str, PyEnum):
    HOSPITAL = "HOSPITAL"
    SCHOOL = "SCHOOL"
    BRIDGE = "BRIDGE"
    GOVERNMENT_BUILDING = "GOVERNMENT_BUILDING"
    POWER_STATION = "POWER_STATION"
    COMMUNICATION_TOWER = "COMMUNICATION_TOWER"
    HELIPAD = "HELIPAD"
    OTHER = "OTHER"


class Road(Base):
    __tablename__ = "roads"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    road_number: Mapped[str | None] = mapped_column(String(100), nullable=True)  # e.g. NH-27
    category: Mapped[str] = mapped_column(String(100), default="NATIONAL_HIGHWAY", nullable=False) # HIGHWAY, STATE_ROAD, LOCAL
    
    # PostGIS LINESTRING Geometry (SRID 4326)
    geometry: Mapped[str] = mapped_column(
        Geometry(geometry_type="LINESTRING", srid=4326), nullable=False
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Village(Base):
    __tablename__ = "villages"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    district: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    state: Mapped[str] = mapped_column(String(100), default="Assam", nullable=False)
    population: Mapped[int | None] = mapped_column(Integer, nullable=True)

    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)

    # PostGIS POINT Geometry (SRID 4326)
    location: Mapped[str] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326), nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Infrastructure(Base):
    __tablename__ = "infrastructure"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    category: Mapped[InfrastructureCategory] = mapped_column(
        Enum(InfrastructureCategory, name="infrastructure_category"), nullable=False, index=True
    )
    district: Mapped[str] = mapped_column(String(100), nullable=False)

    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)

    # PostGIS POINT Geometry (SRID 4326)
    location: Mapped[str] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326), nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


# GIST Spatial Indexes
Index("idx_roads_geometry", Road.geometry, postgresql_using="gist")
Index("idx_villages_location", Village.location, postgresql_using="gist")
Index("idx_infrastructure_location", Infrastructure.location, postgresql_using="gist")
