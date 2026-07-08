from sqlalchemy.orm import Session

from ..models.user import User
from ..models.loan import Loan


class DirectorLoanAccessDeniedError(Exception):
    """Raised when a non-superadmin user tries to read or write a loan
    belonging to a director. Routers translate this into a 403."""
    pass


def _enforce_director_privacy(loan_party_type: str, user: User) -> None:
    """
    Central checkpoint for the director-financial-privacy rule.

    loans is polymorphic (party_type: employee/director/vendor), so this check
    can't live in a route's role dependency alone the way DIRECTOR_ROLES does
    for the dedicated /directors endpoints — a loan row's sensitivity depends
    on data (party_type), not just which endpoint was called. Every function
    below that reads or writes a loan must call this before touching the row.
    """
    if loan_party_type == "director" and user.role != "superadmin":
        raise DirectorLoanAccessDeniedError(
            "Loans belonging to a director are visible to superadmin only."
        )


def get_loan(db: Session, loan_id: int, user: User) -> Loan:
    loan = db.query(Loan).filter(Loan.loan_id == loan_id).first()
    if loan is not None:
        _enforce_director_privacy(loan.party_type, user)
    return loan


def list_loans(db: Session, user: User, party_type: str | None = None, party_id: int | None = None):
    query = db.query(Loan)
    if party_type:
        query = query.filter(Loan.party_type == party_type)
    if party_id:
        query = query.filter(Loan.party_id == party_id)

    # A non-superadmin user querying broadly (no party_type filter) should
    # never see director rows mixed into the results — filter them out
    # rather than erroring, since "list all loans" is a legitimate call for
    # an admin as long as director rows are excluded, not rejected outright.
    if user.role != "superadmin":
        query = query.filter(Loan.party_type != "director")

    return query.all()


def update_loan_payment(db: Session, loan_id: int, paid_amount: float, user: User) -> Loan:
    loan = db.query(Loan).filter(Loan.loan_id == loan_id).first()
    if loan is None:
        return None
    _enforce_director_privacy(loan.party_type, user)  # raises before any write happens

    loan.paid_amount = paid_amount
    db.commit()
    db.refresh(loan)
    return loan
