-- School ERP: Sample Seed Data
-- Load AFTER running finance_payroll_schema.sql and auth_audit_schema.sql.
-- All names/emails/amounts below are fictional test data, not real school records.
--
-- Order matters: this respects the same foreign-key dependency order the
-- schema itself was built in.

-- ============================================================
-- 1. vendor_categories
-- ============================================================
INSERT INTO vendor_categories (name) VALUES
    ('Fuel'), ('Electrician'), ('Stationery'), ('Utility');

-- ============================================================
-- 2. employees
-- ============================================================
INSERT INTO employees (full_name, designation, employment_type, bank_status, contact_no, email) VALUES
    ('Anita Sharma', 'Teacher', 'permanent', 'online', '9876500001', 'anita.sharma@example.com'),
    ('Ravi Kumar',   'Peon',    'permanent', 'cash',   '9876500002', 'ravi.kumar@example.com'),
    ('Fatima Khan',  'Driver',  'contract',  'online', '9876500003', 'fatima.khan@example.com');

-- ============================================================
-- 3. vendors
-- ============================================================
INSERT INTO vendors (name, category_id, contact_no, email, bank_account_no) VALUES
    ('Kalyan Fuel Center',   1, '9876511111', 'kalyan.fuel@example.com',      'ACC1001'),
    ('Sharma Electricals',   2, '9876522222', 'sharma.elec@example.com',      'ACC1002'),
    ('City Stationery Mart', 3, '9876533333', 'city.stationery@example.com', 'ACC1003');

-- ============================================================
-- 4. directors
-- ============================================================
INSERT INTO directors (full_name, contact_no, email) VALUES
    ('Director One', '9876544444', 'director.one@example.com'),
    ('Director Two', '9876555555', 'director.two@example.com');

-- ============================================================
-- 5. payroll_periods
-- ============================================================
INSERT INTO payroll_periods (period_month, period_year) VALUES
    (7, 2026), (8, 2026);

-- ============================================================
-- 6. users (moved up here so we can set the audit session variable below —
--    users has no dependency on the tables that follow)
--    NOTE: these password_hash values are placeholders, NOT real bcrypt
--    hashes — never use these strings as actual credentials.
-- ============================================================
INSERT INTO users (username, full_name, email, password_hash, role) VALUES
    ('priya_superadmin', 'Priya Singh',  'priya.super@example.com',     'PLACEHOLDER_HASH_0', 'superadmin'),
    ('ramesh_accountant','Ramesh Gupta', 'ramesh.accountant@example.com','PLACEHOLDER_HASH_1', 'accountant'),
    ('sunita_dataentry', 'Sunita Devi',  'sunita.entry@example.com',    'PLACEHOLDER_HASH_2', 'data_entry');

-- Set the session variable the audit trigger reads, so changed_by gets
-- populated below instead of staying NULL. In your real app, FastAPI would
-- run this once per request (SET LOCAL, inside a transaction); here we set
-- it for the whole session since this is just a manual test load.
SET app.current_user_id = '2';  -- pretend we're logged in as ramesh_accountant

-- ============================================================
-- 7. employee_advances
-- ============================================================
INSERT INTO employee_advances (employee_id, amount, date_given) VALUES
    (1, 5000.00, '2026-07-05'),
    (2, 2000.00, '2026-07-10');

-- ============================================================
-- 8. payroll_entries
-- ============================================================
INSERT INTO payroll_entries
    (employee_id, period_id, days_worked, base_amount, security_deposit,
     security_deduction, advance_id, advance_deducted, salary_paid, notes)
VALUES
    (1, 1, 26.0, 30000.00, 5000.00, 0, 1, 2000.00, 28000.00, 'July salary, advance partially deducted'),
    (2, 1, 25.5, 15000.00, 0,       0, 2, 1000.00, 14000.00, NULL),
    (3, 1, 26.0, 18000.00, 0,       0, NULL, 0,     18000.00, NULL);

-- ============================================================
-- 9. recurring_bills
-- ============================================================
INSERT INTO recurring_bills (vendor_id, description, expected_amount, frequency) VALUES
    (1, 'Vehicle EMI',       12000.00, 'monthly'),
    (2, 'Electricity bill',   8000.00, 'monthly');

-- ============================================================
-- 10. vendor_transactions
-- ============================================================
INSERT INTO vendor_transactions
    (vendor_id, recurring_bill_id, description, amount, paid_amount, transaction_date, reference_no)
VALUES
    (1, 1,    'July EMI payment',        12000.00, 12000.00, '2026-07-03', 'EMI-JUL-26'),
    (2, 2,    'July electricity bill',    8200.00,  8200.00,  '2026-07-07', 'ELEC-JUL-26'),
    (3, NULL, 'Notebooks and registers',  3500.00,  3500.00,  '2026-07-12', 'BILL-2210');

-- ============================================================
-- 11. director_draws
-- ============================================================
INSERT INTO director_draws (director_id, period_id, previous_balance, new_draw, paid_amount, notes) VALUES
    (1, 1, 0, 20000.00, 20000.00, 'July draw, paid in full'),
    (2, 1, 0, 15000.00, 10000.00, 'Partially paid this month');

-- ============================================================
-- 12. loans (one per party_type, to exercise every branch of
--     fn_validate_loan_party)
-- ============================================================
INSERT INTO loans (party_type, party_id, principal_amount, interest_amount, paid_amount, start_date) VALUES
    ('employee', 2, 10000.00, 500.00, 2000.00,  '2026-06-01'),
    ('director', 1, 50000.00, 0,      10000.00, '2026-05-15'),
    ('vendor',   3, 5000.00,  0,      0,         '2026-07-01');

-- ============================================================
-- VERIFICATION QUERIES — run these after loading the data above
-- ============================================================

-- Confirm generated balance columns computed themselves correctly:
-- SELECT entry_id, base_amount, salary_paid, balance FROM payroll_entries;
-- SELECT loan_id, party_type, principal_amount, interest_amount, paid_amount, balance FROM loans;

-- Confirm the audit trigger fired and captured changed_by:
-- SELECT table_name, record_id, action, changed_by, changed_at FROM audit_log ORDER BY changed_at;
-- Expect 15 rows as of the trg_audit_recurring_bills addition (2 recurring_bills + 2 employee_advances
-- + 3 payroll_entries + 3 vendor_transactions + 2 director_draws + 3 loans), all changed_by = 2.

-- Confirm the recurring_bill_id link works:
-- SELECT vt.transaction_id, vt.description, rb.description AS recurring_bill
-- FROM vendor_transactions vt
-- LEFT JOIN recurring_bills rb ON vt.recurring_bill_id = rb.recurring_bill_id;

-- ============================================================
-- NEGATIVE TESTS — every one of these should FAIL.
-- Run each individually (wrapped in a transaction you roll back) to confirm
-- the schema actually rejects bad data instead of silently accepting it.
-- Postgres aborts the whole transaction after an error, so ROLLBACK first
-- if you're testing these interactively in the same session as the seed data.
-- ============================================================

-- 1. Invalid party_type (violates the CHECK constraint)
-- BEGIN;
-- INSERT INTO loans (party_type, party_id, principal_amount) VALUES ('teacher', 1, 1000);
-- ROLLBACK;

-- 2. party_id that doesn't exist for that party_type (violates fn_validate_loan_party trigger)
-- BEGIN;
-- INSERT INTO loans (party_type, party_id, principal_amount) VALUES ('employee', 9999, 1000);
-- ROLLBACK;

-- 3. Invalid period_month (violates the CHECK constraint)
-- BEGIN;
-- INSERT INTO payroll_periods (period_month, period_year) VALUES (13, 2026);
-- ROLLBACK;

-- 4. Duplicate payroll entry for the same employee + period (violates UNIQUE)
-- BEGIN;
-- INSERT INTO payroll_entries (employee_id, period_id, base_amount, salary_paid) VALUES (1, 1, 1000, 1000);
-- ROLLBACK;

-- 5. Duplicate username (violates UNIQUE)
-- BEGIN;
-- INSERT INTO users (username, full_name, email, password_hash) VALUES ('priya_superadmin', 'X', 'x@example.com', 'hash');
-- ROLLBACK;

-- 6. Invalid role (violates the CHECK constraint)
-- BEGIN;
-- INSERT INTO users (username, full_name, email, password_hash, role) VALUES ('test_user', 'Test', 't@example.com', 'hash', 'superuser');
-- ROLLBACK;

-- 7. NULL in a NOT NULL amount column (should reject, not silently zero out balance)
-- BEGIN;
-- INSERT INTO employee_advances (employee_id, amount, amount_deducted) VALUES (1, 1000, NULL);
-- ROLLBACK;







-- ==============================================================================================================
-- EXPECTED ERROR MESSAGES
-- ==============================================================================================================

-- TEST 1 ERROR MESSAGE:
-- "	ERROR:  Unknown party_type: teacher
-- 	CONTEXT:  PL/pgSQL function fn_validate_loan_party() line 12 at RAISE 

-- 	SQL state: P0001	"

-- TEST 2 ERROR MESSAGE:
-- "	ERROR:  loans.party_id 9999 does not exist in the employee table
-- 	CONTEXT:  PL/pgSQL function fn_validate_loan_party() line 16 at RAISE 

-- 	SQL state: P0001	"

-- TEST 3 ERROR MESSAGE:
-- "	ERROR:  new row for relation "payroll_periods" violates check constraint "payroll_periods_period_month_check"
-- 	Failing row contains (3, 13, 2026, open). 

-- 	SQL state: 23514
-- 	Detail: Failing row contains (3, 13, 2026, open).	"

-- TEST 4 ERROR MESSAGE:
-- "	ERROR:  duplicate key value violates unique constraint "payroll_entries_employee_id_period_id_key"
-- 	Key (employee_id, period_id)=(1, 1) already exists. 

-- 	SQL state: 23505
-- 	Detail: Key (employee_id, period_id)=(1, 1) already exists.	"

-- TEST 5 ERROR MESSAGE:
-- "	ERROR:  duplicate key value violates unique constraint "users_username_key"
-- 	Key (username)=(priya_superadmin) already exists. 
-- 	
-- 	SQL state: 23505
-- 	Detail: Key (username)=(priya_superadmin) already exists.	"

-- TEST 6 ERROR MESSAGE: 
-- "	ERROR:  new row for relation "users" violates check constraint "users_role_check	"
-- 	Failing row contains (5, test_user, Test, t@example.com, hash, superuser, t, null, 2026-07-08 14:50:10.553946). 

-- 	SQL state: 23514
-- 	Detail: Failing row contains (5, test_user, Test, t@example.com, hash, superuser, t, null, 2026-07-08 14:50:10.553946).		"

-- TEST 7 ERROR MESSAGE: 
-- "	ERROR:  null value in column "amount_deducted" of relation "employee_advances" violates not-null constraint
-- 	Failing row contains (3, 1, 1000.00, 2026-07-08, null, null, open, null, null, 2026-07-08 14:51:33.854775). 

-- 	SQL state: 23502
-- 	Detail: Failing row contains (3, 1, 1000.00, 2026-07-08, null, null, open, null, null, 2026-07-08 14:51:33.854775).	"

