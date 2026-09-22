"""
app/schemas/media.py

Pydantic schemas for media uploads and metadata.
"""

from datetime import datetime
from uuid import UUID
from typing import Optional
from pydantic import BaseModel, HttpUrl

from app.models.media import MediaType


class MediaCreate(BaseModel):
    media_url: str
    media_type: MediaType = MediaType.IMAGE
    file_size: Optional[int] = None
    file_hash: Optional[str] = None


class MediaResponse(BaseModel):
    id: UUID
    report_id: UUID
    media_url: str
    media_type: MediaType
    file_size: Optional[int] = None
    file_hash: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
