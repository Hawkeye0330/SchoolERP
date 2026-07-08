from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..dependencies import get_current_user, require_role
from ..models.user import User
from ..schemas.payroll import PayrollEntryCreate, PayrollEntryOut
from ..services import payroll_service

router = APIRouter(prefix="/payroll-periods/{period_id}/entries", tags=["payroll"])


@router.get("", response_model=list[PayrollEntryOut])
def list_entries(
    period_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),  # any logged-in user can view
):
    return payroll_service.get_entries_for_period(db, period_id)


@router.post("", response_model=PayrollEntryOut, status_code=status.HTTP_201_CREATED)
def create_entry(
    period_id: int,
    payload: PayrollEntryCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_role("data_entry", "accountant", "admin")),
):
    # Business rule lives in the service, not here — the route just enforces
    # who's allowed to call it and passes the request through.
    try:
        return payroll_service.create_entry(db, period_id, payload, created_by=user.user_id)
    except payroll_service.PeriodClosedError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This payroll period is closed")
    except payroll_service.DuplicateEntryError:
        raise HTTPException(status.HTTP_409_CONFLICT, "This employee already has an entry for this period")
