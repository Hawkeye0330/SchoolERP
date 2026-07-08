-- School ERP: Full Financial Schema
-- Extends the existing Payroll & Expenses module (finance_payroll_schema.sql,
-- auth_audit_schema.sql) into a complete financial system.
-- Target: PostgreSQL 14+
--
-- ASSUMPTIONS MADE (correct these once real school data is available):
--   - Fiscal year runs April 1 -> March 31 (standard for Indian schools)
--   - Generic chart of accounts skeleton (asset/liability/equity/income/expense)
--   - Generic fee heads (tuition, transport, exam, admission, activity)
--   - Straight-line depreciation as the default method
--   - GST/TDS modeled structurally; actual rates/thresholds are a compliance
--     question to confirm with your accountant, not a schema decision

-- ============================================================
-- SECTION 1: FISCAL YEAR STRUCTURE
-- ============================================================

CREATE TABLE fiscal_years (
    fiscal_year_id  SERIAL PRIMARY KEY,
    start_date      DATE NOT NULL,          -- e.g. 2026-04-01
    end_date        DATE NOT NULL,          -- e.g. 2027-03-31
    status          VARCHAR(20) NOT NULL DEFAULT 'open',  -- open, closed
    CHECK (end_date > start_date)
);

-- ============================================================
-- SECTION 2: CHART OF ACCOUNTS & GENERAL LEDGER
-- The backbone everything else eventually posts into.
-- ============================================================

CREATE TABLE accounts (
    account_id      SERIAL PRIMARY KEY,
    account_code    VARCHAR(20) UNIQUE NOT NULL,   -- e.g. '4010'
    account_name    VARCHAR(150) NOT NULL,         -- e.g. 'Tuition Income'
    account_type    VARCHAR(20) NOT NULL CHECK (account_type IN
                        ('asset','liability','equity','income','expense')),
    parent_account_id INT REFERENCES accounts(account_id),  -- for hierarchy, e.g. sub-accounts
    is_active       BOOLEAN DEFAULT TRUE
);

CREATE TABLE journal_entries (
    entry_id        SERIAL PRIMARY KEY,
    fiscal_year_id  INT NOT NULL REFERENCES fiscal_years(fiscal_year_id),
    entry_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    description     VARCHAR(255),
    -- Links this journal entry back to whatever transaction generated it,
    -- e.g. ('payroll_entries', 42) or ('fee_receipts', 108).
    source_table    VARCHAR(50),
    source_id       INT,
    created_by      INT REFERENCES users(user_id),
    created_at      TIMESTAMP DEFAULT now()
);

CREATE TABLE journal_entry_lines (
    line_id         SERIAL PRIMARY KEY,
    entry_id        INT NOT NULL REFERENCES journal_entries(entry_id),
    account_id      INT NOT NULL REFERENCES accounts(account_id),
    debit_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
    credit_amount   NUMERIC(12,2) NOT NULL DEFAULT 0,
    CHECK (
        (debit_amount > 0 AND credit_amount = 0) OR
        (credit_amount > 0 AND debit_amount = 0)
    )
);

CREATE INDEX idx_je_lines_entry ON journal_entry_lines(entry_id);
CREATE INDEX idx_je_lines_account ON journal_entry_lines(account_id);

-- A trial balance, P&L, or balance sheet is a query summing debit/credit per
-- account_id (optionally filtered by account_type and fiscal_year_id) -
-- not a separate table. This is the payoff of modeling it this way.

CREATE TABLE opening_balances (
    opening_balance_id  SERIAL PRIMARY KEY,
    fiscal_year_id      INT NOT NULL REFERENCES fiscal_years(fiscal_year_id),
    account_id          INT NOT NULL REFERENCES accounts(account_id),
    opening_debit       NUMERIC(12,2) NOT NULL DEFAULT 0,
    opening_credit      NUMERIC(12,2) NOT NULL DEFAULT 0,
    UNIQUE (fiscal_year_id, account_id)
);

-- ============================================================
-- SECTION 3: STUDENTS & FEES (the income side)
-- ============================================================

CREATE TABLE students (
    student_id      SERIAL PRIMARY KEY,
    admission_no    VARCHAR(30) UNIQUE NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    class           VARCHAR(20) NOT NULL,      -- e.g. '8'
    section         VARCHAR(10),                -- e.g. 'B'
    guardian_name   VARCHAR(150),
    guardian_contact VARCHAR(20),
    admission_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'active'  -- active, alumni, withdrawn
);

CREATE TABLE fee_heads (
    fee_head_id     SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,     -- tuition, transport, exam, admission, activity
    account_id      INT REFERENCES accounts(account_id)  -- maps to an income account in the GL
);

CREATE TABLE fee_structures (
    fee_structure_id SERIAL PRIMARY KEY,
    fiscal_year_id  INT NOT NULL REFERENCES fiscal_years(fiscal_year_id),
    class           VARCHAR(20) NOT NULL,
    fee_head_id     INT NOT NULL REFERENCES fee_heads(fee_head_id),
    amount          NUMERIC(10,2) NOT NULL,
    UNIQUE (fiscal_year_id, class, fee_head_id)
);

CREATE TABLE invoices (
    invoice_id      SERIAL PRIMARY KEY,
    student_id      INT NOT NULL REFERENCES students(student_id),
    fiscal_year_id  INT NOT NULL REFERENCES fiscal_years(fiscal_year_id),
    fee_head_id     INT NOT NULL REFERENCES fee_heads(fee_head_id),
    due_date        DATE NOT NULL,
    amount          NUMERIC(10,2) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'  -- pending, partially_paid, paid, overdue
);

CREATE TABLE fee_concessions (
    concession_id   SERIAL PRIMARY KEY,
    student_id      INT NOT NULL REFERENCES students(student_id),
    fee_head_id     INT REFERENCES fee_heads(fee_head_id),   -- NULL = applies to all heads
    concession_type VARCHAR(50),      -- sibling_discount, staff_ward, scholarship
    percent_off     NUMERIC(5,2),     -- e.g. 10.00 for 10%
    flat_amount_off NUMERIC(10,2),    -- alternative to a percentage
    approved_by     INT REFERENCES users(user_id),
    CHECK (percent_off IS NOT NULL OR flat_amount_off IS NOT NULL)
);

CREATE TABLE fee_receipts (
    receipt_id      SERIAL PRIMARY KEY,
    invoice_id      INT NOT NULL REFERENCES invoices(invoice_id),
    student_id      INT NOT NULL REFERENCES students(student_id),
    amount_paid     NUMERIC(10,2) NOT NULL,
    payment_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    payment_mode    VARCHAR(20) NOT NULL,  -- cash, cheque, online, upi
    receipt_no      VARCHAR(40) UNIQUE,
    journal_entry_id INT REFERENCES journal_entries(entry_id)  -- posts income to the GL
);

CREATE TABLE fee_refunds (
    refund_id       SERIAL PRIMARY KEY,
    receipt_id      INT NOT NULL REFERENCES fee_receipts(receipt_id),
    amount          NUMERIC(10,2) NOT NULL,
    reason          VARCHAR(200),
    refund_date     DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX idx_invoices_student ON invoices(student_id);
CREATE INDEX idx_receipts_student ON fee_receipts(student_id);

-- ============================================================
-- SECTION 4: BUDGETING
-- ============================================================

CREATE TABLE budgets (
    budget_id       SERIAL PRIMARY KEY,
    fiscal_year_id  INT NOT NULL REFERENCES fiscal_years(fiscal_year_id),
    account_id      INT NOT NULL REFERENCES accounts(account_id),
    budgeted_amount NUMERIC(12,2) NOT NULL,
    approved_by     INT REFERENCES users(user_id),
    approved_at     TIMESTAMP,
    UNIQUE (fiscal_year_id, account_id)
);
-- Actual-vs-budget is a query joining this table against journal_entry_lines
-- for the same account_id and fiscal_year_id — not a stored value.

-- ============================================================
-- SECTION 5: BANKING & CASH
-- ============================================================

CREATE TABLE bank_accounts (
    bank_account_id SERIAL PRIMARY KEY,
    account_name    VARCHAR(150) NOT NULL,   -- e.g. 'HDFC - Main Operating Account'
    account_no      VARCHAR(40) NOT NULL,
    ifsc_code       VARCHAR(15),
    bank_name       VARCHAR(100),
    is_active       BOOLEAN DEFAULT TRUE
);

CREATE TABLE bank_transactions (
    bank_transaction_id SERIAL PRIMARY KEY,
    bank_account_id INT NOT NULL REFERENCES bank_accounts(bank_account_id),
    transaction_date DATE NOT NULL,
    amount          NUMERIC(12,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN
                        ('deposit','withdrawal','transfer')),
    description     VARCHAR(200),
    journal_entry_id INT REFERENCES journal_entries(entry_id)
);

CREATE TABLE bank_reconciliation (
    reconciliation_id SERIAL PRIMARY KEY,
    bank_transaction_id INT NOT NULL REFERENCES bank_transactions(bank_transaction_id),
    journal_entry_line_id INT REFERENCES journal_entry_lines(line_id),
    matched         BOOLEAN NOT NULL DEFAULT FALSE,
    matched_at      TIMESTAMP,
    matched_by      INT REFERENCES users(user_id)
);

CREATE TABLE cheques (
    cheque_id       SERIAL PRIMARY KEY,
    bank_account_id INT NOT NULL REFERENCES bank_accounts(bank_account_id),
    cheque_no       VARCHAR(30) NOT NULL,
    payee_name      VARCHAR(150) NOT NULL,
    amount          NUMERIC(10,2) NOT NULL,
    issue_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'issued'  -- issued, cleared, bounced, cancelled
);

-- ============================================================
-- SECTION 6: STATUTORY & COMPLIANCE
-- ============================================================

CREATE TABLE statutory_challans (
    challan_id      SERIAL PRIMARY KEY,
    challan_type    VARCHAR(20) NOT NULL CHECK (challan_type IN ('EPF','ESI','TDS','PT')),
    period_month    SMALLINT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    period_year     SMALLINT NOT NULL,
    amount          NUMERIC(10,2) NOT NULL,
    due_date        DATE NOT NULL,
    filed_date      DATE,
    challan_no      VARCHAR(50),
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'  -- pending, filed, overdue
);

-- Extends the existing vendors table with tax identifiers needed for TDS/GST compliance.
ALTER TABLE vendors ADD COLUMN pan_no VARCHAR(15);
ALTER TABLE vendors ADD COLUMN gst_no VARCHAR(20);

-- ============================================================
-- SECTION 7: FIXED ASSETS
-- ============================================================

CREATE TABLE fixed_assets (
    asset_id            SERIAL PRIMARY KEY,
    name                VARCHAR(150) NOT NULL,       -- e.g. 'School Bus - RJ14 XX 1234'
    category            VARCHAR(60),                  -- building, vehicle, furniture, computer, etc.
    purchase_date       DATE NOT NULL,
    purchase_cost       NUMERIC(12,2) NOT NULL,
    depreciation_method VARCHAR(30) NOT NULL DEFAULT 'straight_line',
    useful_life_years   INT,
    current_book_value  NUMERIC(12,2) NOT NULL,
    location            VARCHAR(150),
    is_active           BOOLEAN DEFAULT TRUE
);

CREATE TABLE asset_depreciation_log (
    log_id              SERIAL PRIMARY KEY,
    asset_id            INT NOT NULL REFERENCES fixed_assets(asset_id),
    fiscal_year_id      INT NOT NULL REFERENCES fiscal_years(fiscal_year_id),
    depreciation_amount NUMERIC(10,2) NOT NULL,
    book_value_after    NUMERIC(12,2) NOT NULL,
    UNIQUE (asset_id, fiscal_year_id)
);

-- Extends the existing loans table (from finance_payroll_schema.sql) with a
-- proper installment-by-installment schedule instead of one aggregate balance.
CREATE TABLE loan_installments (
    installment_id  SERIAL PRIMARY KEY,
    loan_id         INT NOT NULL REFERENCES loans(loan_id),
    due_date        DATE NOT NULL,
    amount_due      NUMERIC(10,2) NOT NULL,
    amount_paid     NUMERIC(10,2) NOT NULL DEFAULT 0,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'  -- pending, paid, overdue
);

-- ============================================================
-- SECTION 8: INTEGRATION WITH THE EXISTING PAYROLL/EXPENSES MODULE
-- Links the transactions you already built to the new general ledger,
-- so payroll and vendor payments can post into accounts automatically.
-- ============================================================

ALTER TABLE payroll_entries      ADD COLUMN journal_entry_id INT REFERENCES journal_entries(entry_id);
ALTER TABLE vendor_transactions  ADD COLUMN journal_entry_id INT REFERENCES journal_entries(entry_id);
ALTER TABLE director_draws       ADD COLUMN journal_entry_id INT REFERENCES journal_entries(entry_id);
ALTER TABLE loans                ADD COLUMN journal_entry_id INT REFERENCES journal_entries(entry_id);
