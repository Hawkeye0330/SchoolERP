-- School ERP: Finance & Payroll Module
-- Normalized replacement for the legacy "Dashboard / Advance / Pending Salary / Sept Salary" spreadsheet
-- Target: PostgreSQL 14+

-- ============================================================
-- CORE PARTY TABLES
-- ============================================================

CREATE TABLE employees (
    employee_id     SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    designation     VARCHAR(100),               -- e.g. Teacher, Peon, Driver
    employment_type VARCHAR(30) DEFAULT 'permanent', -- permanent, contract
    bank_status     VARCHAR(20) DEFAULT 'online',    -- online, cash, ob
    bank_account_no VARCHAR(40),
    contact_no      VARCHAR(20),
    email           VARCHAR(150),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);

CREATE TABLE vendor_categories (
    category_id     SERIAL PRIMARY KEY,
    name            VARCHAR(60) UNIQUE NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE
);

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

CREATE TABLE directors (
    director_id     SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    contact_no      VARCHAR(20),
    email           VARCHAR(150),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);

-- ============================================================
-- PAYROLL
-- ============================================================

CREATE TABLE payroll_periods (
    period_id       SERIAL PRIMARY KEY,
    period_month    SMALLINT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    period_year     SMALLINT NOT NULL,
    status          VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    UNIQUE (period_month, period_year)
);

CREATE TABLE payroll_entries (
    entry_id            SERIAL PRIMARY KEY,
    employee_id         INT NOT NULL REFERENCES employees(employee_id),
    period_id           INT NOT NULL REFERENCES payroll_periods(period_id),
    days_worked         NUMERIC(4,1) NOT NULL DEFAULT 0,
    base_amount         NUMERIC(10,2) NOT NULL DEFAULT 0,
    security_deposit    NUMERIC(10,2) NOT NULL DEFAULT 0,   -- outstanding security held
    security_deduction  NUMERIC(10,2) NOT NULL DEFAULT 0,
    advance_id          INT,   -- FK to employee_advances added via ALTER TABLE below, once that table exists
    advance_deducted    NUMERIC(10,2) NOT NULL DEFAULT 0,
    salary_paid         NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance             NUMERIC(10,2) GENERATED ALWAYS AS (base_amount - salary_paid) STORED,
    notes               TEXT,
    UNIQUE (employee_id, period_id)
);

CREATE TABLE employee_advances (
    advance_id      SERIAL PRIMARY KEY,
    employee_id     INT NOT NULL REFERENCES employees(employee_id),
    amount          NUMERIC(10,2) NOT NULL,
    date_given      DATE NOT NULL DEFAULT CURRENT_DATE,
    amount_deducted NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance         NUMERIC(10,2) GENERATED ALWAYS AS (amount - amount_deducted) STORED,
    status          VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'cleared'))
);

-- Now that employee_advances exists, link payroll_entries.advance_id to the
-- specific advance a given month's deduction pays down.
ALTER TABLE payroll_entries
    ADD CONSTRAINT fk_payroll_entries_advance
    FOREIGN KEY (advance_id) REFERENCES employee_advances(advance_id);

-- ============================================================
-- VENDOR / RECURRING BILLS
-- ============================================================

CREATE TABLE recurring_bills (
    recurring_bill_id SERIAL PRIMARY KEY,
    vendor_id       INT NOT NULL REFERENCES vendors(vendor_id),
    description     VARCHAR(200) NOT NULL,   -- e.g. 'Vehicle EMI', 'Electricity bill'
    expected_amount NUMERIC(10,2),           -- typical/expected amount, informational only
    frequency       VARCHAR(20) NOT NULL DEFAULT 'monthly'
                        CHECK (frequency IN ('monthly', 'quarterly', 'yearly')),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT now()
);

CREATE TABLE vendor_transactions (
    transaction_id  SERIAL PRIMARY KEY,
    vendor_id       INT NOT NULL REFERENCES vendors(vendor_id),
    recurring_bill_id INT REFERENCES recurring_bills(recurring_bill_id),
    description     VARCHAR(200),
    amount          NUMERIC(10,2) NOT NULL,
    paid_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance         NUMERIC(10,2) GENERATED ALWAYS AS (amount - paid_amount) STORED,
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    reference_no    VARCHAR(60)                  -- bill no / vehicle no, etc.
);

-- ============================================================
-- DIRECTOR DRAWS
-- ============================================================

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

-- ============================================================
-- LOANS (any party type: employee, director, vendor)
-- ============================================================

CREATE TABLE loans (
    loan_id         SERIAL PRIMARY KEY,
    party_type      VARCHAR(20) NOT NULL CHECK (party_type IN ('employee','director','vendor')),
                        -- ACCESS NOTE: rows where party_type = 'director' are restricted to the
                        -- superadmin role only (not admin) — enforced in loan_service.py, not here,
                        -- since Postgres has no per-row visibility rule in this schema (see RLS
                        -- as a future option if this ever needs database-level enforcement).
    party_id        INT NOT NULL,                -- resolved in application layer against the matching table
    principal_amount NUMERIC(10,2) NOT NULL,
    interest_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    paid_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
    balance         NUMERIC(10,2) GENERATED ALWAYS AS (principal_amount + interest_amount - paid_amount) STORED,
    start_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'closed', 'defaulted')),
                        -- NOTE: nothing here automatically flips status when balance reaches 0,
                        -- or marks 'defaulted' — that transition logic belongs in the service
                        -- layer (loan_service.py), not the database, and still needs to be built.
    notes           TEXT
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_payroll_entries_period ON payroll_entries(period_id);
CREATE INDEX idx_payroll_entries_employee ON payroll_entries(employee_id);
CREATE INDEX idx_vendor_transactions_vendor ON vendor_transactions(vendor_id);
CREATE INDEX idx_vendor_transactions_recurring ON vendor_transactions(recurring_bill_id);
CREATE INDEX idx_vendors_category ON vendors(category_id);
CREATE INDEX idx_loans_party ON loans(party_type, party_id);
CREATE INDEX idx_advances_employee ON employee_advances(employee_id);
