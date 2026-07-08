from fastapi import Depends, HTTPException, Cookie, status
from sqlalchemy.orm import Session
from datetime import datetime

from .database import get_db
from .models.user import User
from .models.session import Session as SessionModel

# Role groups — defined once, used everywhere, so the superadmin/admin
# relationship stays consistent instead of being hand-typed on every route.
#
# superadmin has every ability admin has, EXCEPT for directors data, where
# it's the reverse: superadmin gets EXCLUSIVE access and admin is deliberately
# excluded. That's why ADMIN_ROLES and DIRECTOR_ROLES are separate constants,
# not one derived from the other.
ADMIN_ROLES = ("admin", "superadmin")          # use wherever "admin" used to be listed alone
DIRECTOR_ROLES = ("superadmin",)                # directors resource — admin excluded on purpose


def get_current_user(
    session_token: str | None = Cookie(default=None),
    db: Session = Depends(get_db),
) -> User:
    if session_token is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not logged in")

    session = db.query(SessionModel).filter(
        SessionModel.session_token == session_token
    ).first()

    if session is None or session.expires_at < datetime.utcnow():
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired, please log in again")

    user = db.query(User).filter(User.user_id == session.user_id).first()
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Account disabled")

    return user


def require_role(*allowed_roles: str):
    """
    Usage in a route:
        @router.post("/payroll-periods")
        def open_period(user: User = Depends(require_role("accountant", "admin"))):
            ...
    Keeps the permission check declarative and visible right in the route signature,
    instead of buried inside the function body.
    """
    def role_checker(user: User = Depends(get_current_user)) -> User:
        if user.role not in allowed_roles:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                f"This action requires one of: {', '.join(allowed_roles)}",
            )
        return user
    return role_checker
