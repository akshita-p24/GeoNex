from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class AlertConfig(Base):
    __tablename__ = "alert_config"

    config_key: Mapped[str] = mapped_column(
        String,
        primary_key=True,
    )

    config_value: Mapped[str] = mapped_column(
        String,
        nullable=False,
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    updated_by: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )