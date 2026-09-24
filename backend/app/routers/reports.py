from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.dependencies import get_current_user, require_roles
from app.models.audit_log import AuditLog
from app.models.field_report import (
    FieldReport,
    ReportStatus,
)
from app.models.field_verification import (
    FieldVerification,
    VerificationDecision,
)
from app.models.user import User, UserRole
from app.schemas.field_report import (
    FieldReportCreate,
    FieldReportResponse,
)
from app.schemas.field_verification import (
    VerificationRequest,
    VerificationResponse,
)

router = APIRouter(
    prefix="/reports",
    tags=["Field Reports"],
)
# ============================================================
# CREATE FIELD REPORT
# ============================================================

@router.post(
    "",
    response_model=FieldReportResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_field_report(
    report_in: FieldReportCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Submit a geo-tagged field/landslide report.

    M6 Offline Sync:
    - Mobile client can create a report while offline.
    - The client generates a unique client_report_id.
    - When internet connectivity returns, the same report
      can be synchronized with the backend.
    - If the client_report_id already exists, the existing
      report is returned instead of creating a duplicate.

    PostGIS:
    - Creates a POINT geometry from longitude/latitude.
    - SRID 4326 is used.
    """

    # --------------------------------------------------------
    # Offline synchronization / idempotency check
    # --------------------------------------------------------

    if report_in.client_report_id:
        existing_result = await db.execute(
            select(FieldReport)
            .options(
                selectinload(FieldReport.media)
            )
            .where(
                FieldReport.client_report_id
                == report_in.client_report_id
            )
        )

        existing_report = existing_result.scalar_one_or_none()

        if existing_report:
            return existing_report

    # --------------------------------------------------------
    # Create PostGIS POINT
    # --------------------------------------------------------

    point_geom = (
        f"SRID=4326;"
        f"POINT({report_in.longitude} {report_in.latitude})"
    )

    # --------------------------------------------------------
    # Create report
    # --------------------------------------------------------

    report = FieldReport(
        user_id=current_user.id,
        client_report_id=report_in.client_report_id,
        report_type=report_in.report_type,
        description=report_in.description,
        latitude=report_in.latitude,
        longitude=report_in.longitude,
        location=point_geom,
        capture_timestamp=report_in.capture_timestamp,
        status=ReportStatus.PENDING,
    )

    db.add(report)

    await db.commit()

    # --------------------------------------------------------
    # Re-fetch with media eagerly loaded
    #
    # This prevents:
    # MissingGreenlet
    #
    # FastAPI response serialization should never trigger
    # an async lazy-load of FieldReport.media.
    # --------------------------------------------------------

    result = await db.execute(
        select(FieldReport)
        .options(
            selectinload(FieldReport.media)
        )
        .where(
            FieldReport.id == report.id
        )
    )

    report = result.scalar_one()

    return report


# ============================================================
# LIST FIELD REPORTS
# ============================================================

@router.get(
    "",
    response_model=list[FieldReportResponse],
)
async def list_field_reports(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Return field reports.

    FIELD_OFFICER:
        Returns reports submitted by the current officer.

    Other authenticated users:
        Returns all reports.
    """

    query = (
        select(FieldReport)
        .options(
            selectinload(FieldReport.media)
        )
        .order_by(
            FieldReport.created_at.desc()
        )
    )

    if current_user.role == UserRole.FIELD_OFFICER:
        query = query.where(
            FieldReport.user_id == current_user.id
        )

    result = await db.execute(query)

    reports = result.scalars().unique().all()

    return reports


# ============================================================
# FIELD REPORT GEOJSON
# ============================================================

@router.get(
    "/geojson",
)
async def get_reports_geojson(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Return field reports as GeoJSON FeatureCollection.

    Useful for:
    - Web map
    - Officer dashboard
    - GIS visualization
    """

    query = (
        select(FieldReport)
        .order_by(
            FieldReport.created_at.desc()
        )
    )

    if current_user.role == UserRole.FIELD_OFFICER:
        query = query.where(
            FieldReport.user_id == current_user.id
        )

    result = await db.execute(query)

    reports = result.scalars().all()

    features = []

    for report in reports:
        features.append(
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [
                        report.longitude,
                        report.latitude,
                    ],
                },
                "properties": {
                    "id": str(report.id),
                    "user_id": str(report.user_id),
                    "client_report_id": (
                        str(report.client_report_id)
                        if report.client_report_id
                        else None
                    ),
                    "report_type": report.report_type.value,
                    "status": report.status.value,
                    "description": report.description,
                    "latitude": report.latitude,
                    "longitude": report.longitude,
                    "capture_timestamp": (
                        report.capture_timestamp.isoformat()
                        if report.capture_timestamp
                        else None
                    ),
                    "created_at": (
                        report.created_at.isoformat()
                        if report.created_at
                        else None
                    ),
                },
            }
        )

    return {
        "type": "FeatureCollection",
        "features": features,
    }


# ============================================================
# GET SINGLE FIELD REPORT
# ============================================================

@router.get(
    "/{report_id}",
    response_model=FieldReportResponse,
)
async def get_field_report(
    report_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Get a single field report.
    """

    result = await db.execute(
        select(FieldReport)
        .options(
            selectinload(FieldReport.media)
        )
        .where(
            FieldReport.id == report_id
        )
    )

    report = result.scalar_one_or_none()

    if report is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Field report not found",
        )

    # Field officers can only access their own reports.
    if (
        current_user.role == UserRole.FIELD_OFFICER
        and report.user_id != current_user.id
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to access this report",
        )

    return report


# ============================================================
# VERIFY FIELD REPORT
# ============================================================

@router.post(
    "/{report_id}/verify",
    response_model=VerificationResponse,
)
async def verify_field_report(
    report_id: UUID,
    verify_in: VerificationRequest,
    current_user: User = Depends(
        require_roles(
            [
                UserRole.FIELD_OFFICER,
                UserRole.ADMIN,
            ]
        )
    ),
    db: AsyncSession = Depends(get_db),
):
    """
    Officer verification workflow.

    Possible decisions:
        VERIFY
        REJECT
        NEEDS_INFORMATION

    Workflow:

        Field Report
              ↓
        Officer Verification
              ↓
        Decision
              ↓
        Report Status Updated
              ↓
        Audit Log Created
    """

    # --------------------------------------------------------
    # Find report
    # --------------------------------------------------------

    result = await db.execute(
        select(FieldReport)
        .where(
            FieldReport.id == report_id
        )
    )

    report = result.scalar_one_or_none()

    if report is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Field report not found",
        )

    # --------------------------------------------------------
    # Prevent duplicate verification
    # --------------------------------------------------------

    existing_verification_result = await db.execute(
        select(FieldVerification)
        .where(
            FieldVerification.report_id == report_id
        )
    )

    existing_verification = (
        existing_verification_result.scalar_one_or_none()
    )

    if existing_verification:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This field report has already been verified",
        )

    # --------------------------------------------------------
    # Map verification decision to report status
    # --------------------------------------------------------

    if verify_in.decision == VerificationDecision.VERIFY:

        new_status = ReportStatus.VERIFIED

    elif verify_in.decision == VerificationDecision.REJECT:

        new_status = ReportStatus.REJECTED

    elif (
        verify_in.decision
        == VerificationDecision.NEEDS_INFORMATION
    ):

        new_status = ReportStatus.NEEDS_INFORMATION

    else:

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid verification decision",
        )

    # --------------------------------------------------------
    # Create verification record
    # --------------------------------------------------------

    verification = FieldVerification(
        report_id=report.id,
        officer_id=current_user.id,
        decision=verify_in.decision,
        remarks=verify_in.remarks,
    )

    db.add(verification)

    # --------------------------------------------------------
    # Update report status
    # --------------------------------------------------------

    report.status = new_status

    # --------------------------------------------------------
    # Create audit log
    #
    # IMPORTANT:
    # Use .value so the audit action becomes:
    #
    # REPORT_VERIFY
    #
    # instead of:
    #
    # REPORT_VerificationDecision.VERIFY
    # --------------------------------------------------------

    audit = AuditLog(
        user_id=current_user.id,
        action=f"REPORT_{verify_in.decision.value}",
        entity_type="FieldReport",
        entity_id=str(report.id),
        details={
            "report_id": str(report.id),
            "officer_id": str(current_user.id),
            "decision": verify_in.decision.value,
            "remarks": verify_in.remarks,
            "new_status": new_status.value,
        },
    )

    db.add(audit)

    # --------------------------------------------------------
    # Commit transaction
    # --------------------------------------------------------

    await db.commit()

    # --------------------------------------------------------
    # Re-fetch verification with relationships loaded
    # --------------------------------------------------------

    verification_result = await db.execute(
        select(FieldVerification)
        .where(
            FieldVerification.id == verification.id
        )
    )

    verification = verification_result.scalar_one()

    return verification