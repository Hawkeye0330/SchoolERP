# Project Status

**Last updated:** _(update this line every time you touch this file)_

## Current phase

**Phase 1 — Backend core** (Weeks 1–3)

## Completed

- [x] Finance & payroll schema designed (`finance_payroll_schema.sql`)
- [x] Auth & audit schema designed (`auth_audit_schema.sql`)
- [x] Two bugs found and fixed (missing NOT NULL constraints, loans.party_id validation)
- [x] API endpoint list designed (all resources, roles, request/response shapes)
- [x] FastAPI route architecture designed (routers/services/models/schemas)
- [x] Example files written: `dependencies.py`, `routers/payroll_entries.py`

## In progress

- [ ] Stand up a real local PostgreSQL instance
- [ ] Run both schema files against it for the first time
- [ ] Set up Alembic for migrations

## Next up (in order)

- [ ] Auth vertical slice: sessions table, login/logout endpoints
- [ ] Employees vertical slice: model, schema, service, router
- [ ] Payroll periods + entries vertical slice (including closed-period enforcement)
- [ ] Vendors vertical slice
- [ ] Advances, then loans vertical slice
- [ ] Reports/dashboard endpoints
- [ ] Audit log endpoint

## Known open questions / decisions deferred

- How to handle the legacy spreadsheet's "Fake vs Actual" salary columns during data migration (Phase 2) — not yet decided.
- Whether the ERP will eventually be sold to other schools (multi-tenancy question) —
  **revisit once the General Ledger module is complete.**

## Longer-term roadmap

See `docs/school_erp_finance_plan.pdf` and `docs/school_financial_system_proposal.pdf` for the
full phased plan, including modules beyond Payroll & Expenses (Fees & Income, General Ledger,
Budgeting, Banking, Compliance, Fixed Assets).
