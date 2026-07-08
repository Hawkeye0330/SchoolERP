# School ERP — Finance & Payroll Module

A module-by-module ERP for St. Xavier Secondary School, starting with Payroll & Expenses.

**Status:** Phase 1 — Backend core (in progress). See [`PROJECT_STATUS.md`](./PROJECT_STATUS.md) for the current state.

## Tech stack

- **Database:** PostgreSQL 14+
- **Backend:** FastAPI + SQLAlchemy + Alembic (migrations)
- **Auth:** Session-cookie based (see `docs/` for the login flow design)
- **Frontend:** React (planned, Phase 3)

## Repo structure

```
app/                    # FastAPI backend code
├── main.py              # FastAPI app entrypoint
├── config.py             # Environment/config
├── database.py            # DB engine, session, get_db()
├── dependencies.py         # get_current_user, require_role, ADMIN_ROLES/DIRECTOR_ROLES
├── core/                   # security.py, exceptions.py
├── models/                 # SQLAlchemy ORM models
├── schemas/                 # Pydantic request/response models
├── services/                 # Business logic (loan_service.py, period-closed checks, etc.)
└── routers/                   # Thin route handlers (payroll_entries.py, etc.)

backend/                # Backend-specific build config (Dockerfile, etc.)
frontend/               # React application code
ui/                     # Design files — Figma exports, mockups, wireframes (not code)

database/               # Executable SQL — actually run against Postgres
├── finance_payroll_schema.sql
├── auth_audit_schema.sql
├── seed_data.sql
└── future/                # Draft schemas for modules not yet built
    └── full_financial_schema.sql

docs/                   # Documentation meant to be read, not run
├── schema_table_report_final.md
├── schema_full_report_final.pdf
├── school_erp_api_endpoints.pdf
└── Master_SRS.md

architecture/           # DFD, ERD, UML diagrams
├── DFD/
├── ERD/
│   └── finance_schema_erd.jpg
└── UML/

assets/                 # Static assets (images, logos)
deployment/             # Cross-cutting orchestration/deploy configs (docker-compose, CI/CD)
testing/                # Test suites
```

## Setup (fill in as Phase 1 progresses)

```bash
# 1. Clone and enter the repo
git clone <repo-url>
cd school-erp

# 2. Create a virtual environment
python -m venv venv
source venv/bin/activate   # or venv\Scripts\activate on Windows

# 3. Install dependencies
pip install -r requirements.txt

# 4. Set up your local .env (copy the example and fill in real values)
cp .env.example .env

# 5. Run the schema against a local PostgreSQL database
psql -U postgres -d school_erp -f database/finance_payroll_schema.sql
psql -U postgres -d school_erp -f database/auth_audit_schema.sql

# 6. Run the app
uvicorn app.main:app --reload
```

## Documentation

Reference documentation — the schema report, API endpoint map, and ER diagram — lives in `docs/`.
Executable schema files live in `database/`, with drafts for future modules under
`database/future/`. Start with [`PROJECT_STATUS.md`](./PROJECT_STATUS.md) (repo root) for where
things currently stand.

## License

Internal project — not currently licensed for external use.
