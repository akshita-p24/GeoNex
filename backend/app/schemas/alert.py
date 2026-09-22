"""
app/schemas/alert.py

Pydantic schemas for early warning alerts (M5).
"""

from datetime import datetime
from uuid import UUID
from typing import Optional
from pydantic import BaseModel

from app.models.risk_prediction import RiskLevel
from app.models.alert import AlertStatus


class AlertResponse(BaseModel):
    id: UUID
    risk_prediction_id: Optional[UUID] = None
    severity: RiskLevel
    status: AlertStatus
    title: str
    message: str
    created_at: datetime
    acknowledged_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class AlertAcknowledgeRequest(BaseModel):
    remarks: Optional[str] = None
