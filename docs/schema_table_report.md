# School ERP — Finance & Payroll Schema: Table-by-Table Report

A living document, updated as each table is discussed. Tables are listed in chronological
(build) order — the order they must be created in, since later tables reference earlier ones.

**Progress: 13 of 13 tables covered — complete.**

---

## 1. `employees`

```sql
CREATE TABLE employees (
    employee_id     SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    designation     VARCHAR(100),
    employment_type VARCHAR(30) DEFAULT 'permanent',
    bank_status     VARCHAR(20) DEFAULT 'online',
    bank_account_no VARCHAR(40),
    contact_no      VARCHAR(20),
    email           VARCHAR(150),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);
```

**Purpose:** master record of every staff member. Gives every employee a surrogate ID so nothing
downstream ever has to store or match on a name.

**Fields:**
- `employee_id` — auto-incrementing surrogate key. Referenced by `payroll_entries`,
  `employee_advances`, and (via `party_id`) `loans`.
- `full_name` — required.
- `designation` — job title (Teacher, Peon, Driver). Optional.
- `employment_type` — permanent/contract. Defaults to `'permanent'`.
- `bank_status` — online/cash/ob. Defaults to `'online'`.
- `bank_account_no` — optional, unvalidated format.
- `contact_no` — phone number. *(Added mid-walkthrough for parity with vendors/directors.)*
- `email` — *(added same time as `contact_no`.)*
- `is_active` — soft-delete flag; `FALSE` instead of a real delete, since payroll history
  references this row.
- `created_at` — auto-stamped via `now()`.

**Special concerns:**
- No `created_by`/`updated_by` — that accountability layer only applies to *transactional* tables,
  not foundation/master tables. Consistent choice, but worth remembering if you ever want to know
  who added or edited an employee record.

---

## 2. `vendor_categories`

```sql
CREATE TABLE vendor_categories (
    category_id     SERIAL PRIMARY KEY,
    name            VARCHAR(60) UNIQUE NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE
);
```

**Purpose:** a fixed, managed list of vendor categories (fuel, electrician, stationery, etc.),
added specifically to stop free-text category values like `"Fuel"` / `"fuel "` / `"FUEL"` from
being treated as different categories. *(Added mid-walkthrough, before `vendors`.)*

**Fields:**
- `category_id` — surrogate key, referenced by `vendors.category_id`.
- `name` — `UNIQUE` (the first single-column uniqueness constraint in the schema) and required.
- `is_active` — soft-delete flag.

**Special concerns:**
- Deliberately has **no `created_at`** — decided this is closer to a fixed configuration list than
  a record worth tracing back to a creation date, unlike the party tables.

---

## 3. `vendors`

```sql
CREATE TABLE vendors (
    vendor_id       SERIAL PRIMARY KEY,
    name            VARCHAR(150) NOT NULL,
    category_id     INT REFERENCES vendor_categories(category_id),
    contact_no      VARCHAR(20),
    email           VARCHAR(150),
    bank_account_no VARCHAR(40),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);
```

**Purpose:** master record of every vendor (shop, contractor, supplier) the school pays. Same
surrogate-key reasoning as `employees`.

**Fields:**
- `vendor_id` — surrogate key. Referenced by `vendor_transactions`, `recurring_bills`, and
  (via `party_id`) `loans`.
- `name` — required.
- `category_id` — FK to `vendor_categories`. *(Originally a free-text `category` column;
  normalized into its own table mid-walkthrough.)*
- `contact_no` — phone number, optional, unvalidated.
- `email` — *(added mid-walkthrough for parity with employees/directors.)*
- `bank_account_no` — *(added mid-walkthrough for parity with employees.)*
- `is_active` — soft-delete flag.
- `created_at` — auto-stamped.

**Special concerns:**
- None outstanding — this table has already been brought to parity with `employees` and
  `directors` on contact info and payment details.

---

## 4. `directors`

```sql
CREATE TABLE directors (
    director_id     SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    contact_no      VARCHAR(20),
    email           VARCHAR(150),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);
```

**Purpose:** master record of the school's directors (currently two people). Simplest of the
three party tables.

**Fields:**
- `director_id` — surrogate key. Referenced by `director_draws` and (via `party_id`) `loans`.
- `full_name` — required.
- `contact_no`, `email` — *(both added mid-walkthrough; this table originally had only
  `director_id`, `full_name`, `is_active` — no contact info and no `created_at` at all.)*
- `is_active` — soft-delete flag.
- `created_at` — *(also added mid-walkthrough, to bring this table to parity with `employees`
  and `vendors`.)*

**Special concerns:**
- None outstanding — brought to full parity with the other two party tables.

---

## 5. `payroll_periods`

```sql
CREATE TABLE payroll_periods (
    period_id       SERIAL PRIMARY KEY,
    period_month    SMALLINT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    period_year     SMALLINT NOT NULL,
    status          VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    UNIQUE (period_month, period_year)
);
```

**Purpose:** the first non-"party" table — represents a single calendar month of payroll.
Everything about that month's payroll and director draws anchors to this row.

**Fields:**
- `period_id` — surrogate key. Referenced by `payroll_entries` and `director_draws`.
- `period_month` — 1–12, enforced by `CHECK`. Uses `SMALLINT` (smaller storage than `INT`,
  appropriate since the value never exceeds 12).
- `period_year` — no `CHECK` bound (no meaningful range to enforce).
- `status` — open/closed. **`CHECK` constraint added mid-walkthrough** after discussing whether
  this should be a boolean instead — kept as text for consistency with `employee_advances.status`
  and for room to add a future third state (e.g. `'under_review'`) without a breaking change.
- `UNIQUE (period_month, period_year)` — composite constraint; prevents two "July 2026" rows.

**Special concerns:**
- None outstanding — the missing `CHECK` on `status` was the one gap, now fixed.

---

## 6. `payroll_entries`

```sql
CREATE TABLE payroll_entries (
    entry_id            SERIAL PRIMARY KEY,
    employee_id         INT NOT NULL REFERENCES employees(employee_id),
    period_id           INT NOT NULL REFERENCES payroll_periods(period_id),
    days_worked         NUMERIC(4,1) NOT NULL DEFAULT 0,
    base_amount         NUMERIC(10,2) NOT NULL DEFAULT 0,
    security_deposit    NUMERIC(10,2) NOT NULL DEFAULT 0,
    security_deduction  NUMERIC(10,2) NOT NULL DEFAULT 0,
    advance_id          INT,
    advance_deducted    NUMERIC(10,2) NOT NULL DEFAULT 0,
    salary_paid         NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance             NUMERIC(10,2) GENERATED ALWAYS AS (base_amount - salary_paid) STORED,
    notes               TEXT,
    UNIQUE (employee_id, period_id)
);
-- advance_id's FK constraint is added via ALTER TABLE after employee_advances exists (see below)
```

**Purpose:** the first true transactional table — one employee's actual salary for one specific
month. Where the "who" (`employees`) and "when" (`payroll_periods`) foundation tables actually
meet and produce a real financial record.

**Fields:**
- `entry_id` — surrogate key.
- `employee_id`, `period_id` — required FKs.
- `days_worked` — up to 1 decimal place (e.g. `26.5`).
- `base_amount` — gross salary for the month.
- `security_deposit`, `security_deduction` — **`NOT NULL` added mid-walkthrough** (originally
  nullable — an inconsistency with the rest of the schema's amount columns, fixed even though
  neither feeds the generated `balance` directly).
- `advance_id` — **added mid-walkthrough.** A real FK to `employee_advances(advance_id)`, added
  via a separate `ALTER TABLE` (not inline) because `payroll_entries` is defined before
  `employee_advances` in the file, so Postgres can't reference a table that doesn't exist yet
  at that point in the script.
- `advance_deducted` — the amount; now paired with `advance_id` so the deduction is traceable to
  a specific advance, not just a floating number.
- `salary_paid` — actual amount paid; feeds `balance`.
- `balance` — generated column: `base_amount - salary_paid`.
- `notes` — free-form text.
- `UNIQUE (employee_id, period_id)` — one entry per employee per month.

**Special concerns:**
- **Open item, not yet acted on:** your service layer (`payroll_service.py`) should validate that
  `advance_id`, when set, actually belongs to the *same* `employee_id` as the entry — the FK only
  guarantees the advance exists, not that it belongs to the right person.

---

## 7. `employee_advances`

```sql
CREATE TABLE employee_advances (
    advance_id      SERIAL PRIMARY KEY,
    employee_id     INT NOT NULL REFERENCES employees(employee_id),
    amount          NUMERIC(10,2) NOT NULL,
    date_given      DATE NOT NULL DEFAULT CURRENT_DATE,
    amount_deducted NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance         NUMERIC(10,2) GENERATED ALWAYS AS (amount - amount_deducted) STORED,
    status          VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'cleared'))
);
```

**Purpose:** tracks money given to an employee ahead of payroll. Independent of any specific
`payroll_periods` row — an advance can happen anytime, not tied to a payroll run.

**Fields:**
- `advance_id` — surrogate key. Referenced by `payroll_entries.advance_id`.
- `employee_id` — required FK.
- `amount` — original amount advanced, required, no default.
- `date_given` — defaults to today via `CURRENT_DATE`, but still required.
- `amount_deducted` — **one of the two original bug fixes**: this was missing `NOT NULL` in the
  very first debugging pass, which could have silently broken the generated `balance` below.
- `balance` — generated column: `amount - amount_deducted`.
- `status` — open/cleared. **`CHECK` constraint added mid-walkthrough**, same reasoning as
  `payroll_periods.status`.

**Special concerns:**
- None outstanding.

---

## 8. `recurring_bills`

```sql
CREATE TABLE recurring_bills (
    recurring_bill_id SERIAL PRIMARY KEY,
    vendor_id       INT NOT NULL REFERENCES vendors(vendor_id),
    description     VARCHAR(200) NOT NULL,
    expected_amount NUMERIC(10,2),
    frequency       VARCHAR(20) NOT NULL DEFAULT 'monthly'
                        CHECK (frequency IN ('monthly', 'quarterly', 'yearly')),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);
```

**Purpose:** *(entirely new table, added mid-walkthrough)* represents an ongoing obligation
itself (the vehicle EMI, the electricity bill) as a standing row, separate from any individual
payment. Fixes the original gap where "July's EMI" and "August's EMI" were just two similar-looking
`vendor_transactions` rows with nothing formally connecting them.

**Fields:**
- `recurring_bill_id` — surrogate key. Referenced by `vendor_transactions.recurring_bill_id`.
- `vendor_id` — required FK.
- `description` — required (unlike `vendor_transactions.description`, which is optional) — this
  row *is* the thing being identified.
- `expected_amount` — informational only, not enforced against actual transaction amounts.
- `frequency` — monthly/quarterly/yearly, `CHECK`-constrained from the start (a genuine three-way
  choice, unlike the binary `status` fields elsewhere).
- `is_active` — soft-delete flag.
- `created_at` — added on request; decided this is closer to a financial commitment than a pure
  lookup list (unlike `vendor_categories`), so a creation date is meaningful here.
- `created_by` / `updated_by` / `updated_at` — **added later, to bring this table to full parity**
  with the other five owned financial tables (`payroll_entries`, `employee_advances`,
  `vendor_transactions`, `director_draws`, `loans`).

**Special concerns:**
- **Originally missing its audit trigger** — caught when a test query against `audit_log`
  (after running the negative-test suite live against Postgres) showed 13 rows across five
  tables, with `recurring_bills` conspicuously absent. `trg_audit_recurring_bills` was added
  afterward, along with `created_by`/`updated_by`/`updated_at`, bringing it to the same standard
  as every other financial table. Worth remembering: **any new financial table added in a future
  module needs this same three-part treatment** (audit trigger + ownership columns) — it doesn't
  happen automatically just by creating the table.

---

## 9. `vendor_transactions`

```sql
CREATE TABLE vendor_transactions (
    transaction_id  SERIAL PRIMARY KEY,
    vendor_id       INT NOT NULL REFERENCES vendors(vendor_id),
    recurring_bill_id INT REFERENCES recurring_bills(recurring_bill_id),
    description     VARCHAR(200),
    amount          NUMERIC(10,2) NOT NULL,
    paid_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance         NUMERIC(10,2) GENERATED ALWAYS AS (amount - paid_amount) STORED,
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    reference_no    VARCHAR(60)
);
```

**Purpose:** replaces the old spreadsheet's flat one-balance-per-vendor row with real transaction
history — every bill or payment gets its own row.

**Fields:**
- `transaction_id` — surrogate key.
- `vendor_id` — required FK.
- `recurring_bill_id` — **added mid-walkthrough.** Nullable FK to `recurring_bills`, linking a
  specific payment back to the ongoing obligation it belongs to.
- `description` — optional free text for this specific transaction.
- `amount` — required, no default.
- `paid_amount` — feeds `balance`.
- `balance` — generated column: `amount - paid_amount`.
- `transaction_date` — defaults to today, still required.
- `reference_no` — bill/vehicle number, free text.

**Special concerns:**
- **`is_recurring BOOLEAN` was removed** when `recurring_bill_id` was added — keeping both would
  have let a row claim `is_recurring = true` while `recurring_bill_id` was `NULL` (or vice versa).
  "Is this recurring?" is now simply `recurring_bill_id IS NOT NULL` — one source of truth.

---

## 10. `director_draws`

```sql
CREATE TABLE director_draws (
    draw_id         SERIAL PRIMARY KEY,
    director_id     INT NOT NULL REFERENCES directors(director_id),
    period_id       INT NOT NULL REFERENCES payroll_periods(period_id),
    previous_balance NUMERIC(10,2) NOT NULL DEFAULT 0,
    new_draw       NUMERIC(10,2) NOT NULL DEFAULT 0,
    paid_amount    NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance        NUMERIC(10,2) GENERATED ALWAYS AS (previous_balance + new_draw - paid_amount) STORED,
    notes          TEXT,
    UNIQUE (director_id, period_id)
);
```

**Purpose:** a director's personal draw for a given month — structurally similar to
`payroll_entries` (tied to both a party and a period), kept separate since a draw isn't a salary.
The last table to reuse `payroll_periods` as its calendar anchor.

**Fields:**
- `draw_id` — surrogate key.
- `director_id`, `period_id` — required FKs.
- `previous_balance` — carried forward from the prior period. Correctly `NOT NULL` from the start
  (this table was designed after the first bug-fixing pass, so it didn't inherit that gap).
- `new_draw` — new amount drawn this period.
- `paid_amount` — how much of the total has been paid out.
- `balance` — generated column with **three terms**: `previous_balance + new_draw - paid_amount`
  — the first generated column in the schema with more than two terms.
- `notes` — **added mid-walkthrough**, for parity with `payroll_entries`.
- `UNIQUE (director_id, period_id)` — one draw record per director per month.

**Special concerns:**
- None outstanding.

---

## 11. `loans`

```sql
CREATE TABLE loans (
    loan_id         SERIAL PRIMARY KEY,
    party_type      VARCHAR(20) NOT NULL CHECK (party_type IN ('employee','director','vendor')),
    party_id        INT NOT NULL,
    principal_amount NUMERIC(10,2) NOT NULL,
    interest_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    paid_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance         NUMERIC(10,2) GENERATED ALWAYS AS (principal_amount + interest_amount - paid_amount) STORED,
    start_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'closed', 'defaulted')),
    notes           TEXT
);
```

**Purpose:** the schema's one polymorphic table — a single shared table for a loan held by *any*
of the three party types, since a loan record's shape (principal, interest, paid, balance) is
identical regardless of who holds it.

**Fields:**
- `loan_id` — surrogate key.
- `party_type` — `'employee'`/`'director'`/`'vendor'`, `CHECK`-constrained from the start.
- `party_id` — **the one column in the entire schema with no real `REFERENCES` clause**, since
  Postgres can't point one FK at three different tables. Enforced instead by the
  `fn_validate_loan_party` trigger (`BEFORE INSERT OR UPDATE`), which checks the right table based
  on `party_type` and raises an exception if the ID doesn't exist there.
- `principal_amount` — required, no default.
- `interest_amount`, `paid_amount` — **the second of the two original bug fixes**: both were
  missing `NOT NULL` in the first debugging pass.
- `balance` — generated column: `principal_amount + interest_amount - paid_amount`.
- `start_date` — defaults to today, still required.
- `status` — **added mid-walkthrough.** Three real states (`active`/`closed`/`defaulted`), not
  two — a genuinely good fit for `CHECK`-constrained text rather than a boolean.
- `notes` — **added mid-walkthrough**, same free-form pattern as elsewhere.

**Special concerns:**
- **`'defaulted'` is a judgment call, not something derivable from data.** This schema currently
  has no due-date or installment-schedule tracking on `loans` (just `start_date`), so there's no
  data here that could auto-detect an overdue payment — marking a loan `'defaulted'` will need to
  be a manual action by an accountant/admin, not an automated trigger, unless a proper repayment
  schedule (e.g. a future `loan_installments` table) is added later.
- **Open item, explicitly deferred to the service layer:** nothing here automatically flips
  `status` to `'closed'` when `balance` reaches 0, or sets `'defaulted'`. A comment is left directly
  in the SQL flagging that this transition logic belongs in `loan_service.py`, not the database —
  still needs to be built.
- **Director financial privacy (added after the `users` role redesign):** rows where
  `party_type = 'director'` are restricted to the `superadmin` role only — `admin` is deliberately
  excluded, matching the same restriction placed on `directors` and `director_draws`. This can't be
  enforced by a route-level role dependency alone, since sensitivity here depends on data
  (`party_type`), not the endpoint called — `loan_service.py` checks this on every read and write
  (see `_enforce_director_privacy`), filtering director rows out of broad list queries for
  non-superadmin users rather than erroring outright.

---

## 12. `users`

```sql
CREATE TABLE users (
    user_id         SERIAL PRIMARY KEY,
    username        VARCHAR(50) UNIQUE NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(150) UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    role            VARCHAR(30) NOT NULL DEFAULT 'data_entry'
                        CHECK (role IN ('superadmin', 'admin', 'accountant', 'data_entry', 'viewer')),
    is_active       BOOLEAN DEFAULT TRUE,
    last_login_at   TIMESTAMP,
    created_at      TIMESTAMP DEFAULT now()
);
```

**Purpose:** system access, not staff membership — a different kind of "who" than `employees`.
A person could be an employee with no login, or have a login without being an employee at all
(e.g. an outside accountant). Kept as a separate table for exactly that reason: "who works here"
and "who can log in" are different questions.

**Fields:**
- `user_id` — surrogate key. Referenced by every `created_by`/`updated_by` column across the
  schema, and by `audit_log.changed_by`.
- `username` — `UNIQUE`, required — the login identifier.
- `full_name` — required, same shape as every other `full_name` column in the schema.
- `email` — **originally added with no constraints, then upgraded mid-walkthrough to
  `UNIQUE NOT NULL`** — every user must have an email, and no two users can share one.
- `password_hash` — stores only the bcrypt/argon2 hash, never a raw password. `TEXT` rather than
  `VARCHAR(n)`, since hashes don't map neatly to a small length limit.
- `role` — five flat values now (see Special Concerns below). Defaults to the *least*-privileged
  role (`data_entry`) as a deliberate safety choice — a forgotten role assignment fails safe, not
  over-privileged.
- `is_active` — soft-delete/deactivation flag. Matters more here than almost anywhere else in the
  schema, since deleting a user outright would orphan a large amount of historical accountability
  data (every `created_by`/`updated_by` and `audit_log.changed_by` reference).
- `last_login_at` — nullable, no default; stays `NULL` until the login endpoint explicitly sets it.
  The first column in the schema genuinely meant to start empty rather than default to something
  meaningful on insert.
- `created_at` — same auto-stamped pattern as every other master table.

**Special concerns:**
- **`role`'s `CHECK` constraint was added mid-walkthrough** (originally unconstrained free text —
  a typo like `'admn'` would have silently created a user with no matching role for any
  `require_role(...)` check, rather than erroring at the point the bad value was written).
- **A fifth role, `superadmin`, was added and then fully finalized as its own design decision,**
  not a simple hierarchy:
  - `superadmin` has every ability `admin` has, **plus exclusive access to directors data**
    (`directors`, `director_draws`, and any `loans` row where `party_type = 'director'`).
  - `admin` is **deliberately excluded** from directors data specifically — the one place the
    hierarchy reverses instead of nesting cleanly.
  - Implemented via role-group constants in `dependencies.py` (`ADMIN_ROLES`, `DIRECTOR_ROLES`)
    rather than hand-typed role lists per route, so the relationship can't silently drift out of
    sync across endpoints.
  - Because `loans` is polymorphic, the directors restriction can't be expressed as a route-level
    role check there — `loan_service.py` checks `party_type` on every read/write and
    filters/rejects for anyone below `superadmin`.
  - Confirmed deliberately, not assumed: there will genuinely be more than one admin-tier user, so
    this split was judged to earn its keep rather than being premature complexity.

---

## 13. `audit_log`

```sql
CREATE TABLE audit_log (
    audit_id        BIGSERIAL PRIMARY KEY,
    table_name      VARCHAR(50) NOT NULL,
    record_id       INT NOT NULL,
    action          VARCHAR(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    changed_by      INT REFERENCES users(user_id),
    changed_at      TIMESTAMP DEFAULT now(),
    old_values      JSONB,
    new_values      JSONB
);
```

**Purpose:** the governance layer sitting on top of everything else — not describing money, but
accountability for the money. Populated automatically by database triggers on the five owned
financial tables (`payroll_entries`, `employee_advances`, `vendor_transactions`, `director_draws`,
`loans`), not application code, so a bug in the API layer can't accidentally skip it.

**Fields:**
- `audit_id` — the only `BIGSERIAL` in the schema (every other table uses `SERIAL`). Deliberate:
  this table gains a row on every single change to five other tables combined, so it accumulates
  far faster than anything else — `BIGSERIAL` is cheap insurance against that growth rate.
- `table_name` — which table changed. **Deliberately not a foreign key or CHECK-constrained list**
  — see Special Concerns below.
- `record_id` — the changed row's primary key value. **Also deliberately not a foreign key** — an
  audit log must keep working after the row it describes is gone; a real FK here would either
  block deletion of the original row or cascade and destroy the very history meant to record that
  deletion.
- `action` — `INSERT`/`UPDATE`/`DELETE`, `CHECK`-constrained to exactly the three values `TG_OP`
  can ever hold. This constraint can never actually bind in practice (the trigger only ever
  supplies a valid value) — it's documentation and defense-in-depth more than an active gate.
- `changed_by` — the one real foreign key on this table, to `users`. This is why `users` had to be
  created before `audit_log` in build order. Nullable — if `app.current_user_id` was never set for
  a transaction, this simply stays `NULL` rather than failing the insert.
- `changed_at` — same auto-stamped pattern as every `created_at` elsewhere, named differently since
  it records when the change happened, not when a record was first created.
- `old_values` / `new_values` — the only `JSONB` columns in the schema. Each stores the entire row,
  before and after, via `to_jsonb(OLD)`/`to_jsonb(NEW)` inside the trigger — what lets one table
  audit five structurally different tables without five different audit-table schemas. Trade-off:
  querying "what changed" means reading JSON keys, not plain columns.

**Special concerns:**
- **`table_name` has no `CHECK`/FK constraining it to real table names — confirmed as the right
  call, not just an oversight.** The reasoning: `action`'s valid set is permanently fixed (Postgres
  will never add a fourth trigger event), so its `CHECK` is safe forever. `table_name`'s valid set
  **grows** every time a new table gets an audit trigger (e.g. future Fees module tables) — a
  `CHECK` here would need updating in lockstep, or every write to a newly-audited table would fail
  outright the moment its own audit trigger tried to log it. That failure mode (real financial data
  silently failing to save because a constraint list was forgotten) is worse than the gap it would
  close (a hypothetical stray manual insert into `audit_log`, which is low-stakes and unlikely).
  A soft-guardrail comment was added directly on the column instead of a hard constraint,
  documenting that this column should only ever be populated by `fn_audit_trigger`, never written
  to directly by application code.
- Consistent with `record_id`'s existing design — both columns are intentionally loosely coupled
  to what they're describing, for the same underlying reason.

---

*This document is now complete — all 13 tables in the schema have been covered, in build order,
with every change made mid-walkthrough captured under each table's "Special concerns."*
