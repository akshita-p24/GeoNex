"""
app/routers/alerts.py

Alerts API Endpoints (M5 Integration):
- GET /api/v1/alerts
- GET /api/v1/alerts/{id}
- POST /api/v1/alerts/{id}/acknowledge
"""

from typing import List, Optional
from uuid import UUID
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.alert import Alert, AlertStatus
from app.schemas.alert import AlertResponse, AlertAcknowledgeRequest

router = APIRouter(prefix="/alerts", tags=["Early Warning Alerts"])


@router.get("", response_model=List[AlertResponse])
async def list_alerts(
    status_filter: Optional[AlertStatus] = Query(None, alias="status"),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
):
    """
    Get active and historical early warning alerts (M5 interface).
    """
    query = select(Alert)
    if status_filter:
        query = query.where(Alert.status == status_filter)
    query = query.order_by(Alert.created_at.desc()).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{alert_id}", response_model=AlertResponse)
async def get_alert_by_id(
    alert_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    """
    Get single alert details.
    """
    result = await db.execute(select(Alert).where(Alert.id == alert_id))
    alert = result.scalar_one_or_none()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    return alert


@router.post("/{alert_id}/acknowledge", response_model=AlertResponse)
async def acknowledge_alert(
    alert_id: UUID,
    ack_in: AlertAcknowledgeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Acknowledge an emergency alert by a field officer or district official.
    """
    result = await db.execute(select(Alert).where(Alert.id == alert_id))
    alert = result.scalar_one_or_none()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")

    alert.status = AlertStatus.ACKNOWLEDGED
    alert.acknowledged_at = datetime.now(timezone.utc)
    alert.acknowledged_by = current_user.id

    await db.commit()
    await db.refresh(alert)
    return alert
