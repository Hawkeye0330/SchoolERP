-- School ERP: Auth & Audit Trail addition
-- Layers on top of finance_payroll_schema.sql
-- Target: PostgreSQL 14+

-- ============================================================
-- USERS & ROLES
-- ============================================================

CREATE TABLE users (
    user_id         SERIAL PRIMARY KEY,
    username        VARCHAR(50) UNIQUE NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(150) UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,           -- bcrypt/argon2 hash, hashed in the app layer, never plaintext
    role            VARCHAR(30) NOT NULL DEFAULT 'data_entry'
                        CHECK (role IN ('superadmin', 'admin', 'accountant', 'data_entry', 'viewer')),
        -- superadmin   : highest clearance — everything admin can do, plus whatever is reserved
        --                exclusively for this role as the system grows (e.g. managing admins themselves)
        -- admin        : full access, can manage users
        -- accountant   : can view/edit all finance records, close payroll periods
        -- data_entry   : can enter payroll/vendor data, cannot delete or close periods
        -- viewer       : read-only, e.g. for the director
    is_active       BOOLEAN DEFAULT TRUE,
    last_login_at   TIMESTAMP,
    created_at      TIMESTAMP DEFAULT now()
);

-- Simple role check helper; move to app-layer permission checks as roles grow.
-- If you outgrow these 5 flat roles, split into roles + permissions tables later —
-- not worth the complexity until you actually have overlapping access needs.

-- ============================================================
-- created_by / updated_by ON EVERY FINANCIAL TABLE
-- ============================================================

ALTER TABLE payroll_entries      ADD COLUMN created_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_at TIMESTAMP DEFAULT now();

ALTER TABLE employee_advances    ADD COLUMN created_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_at TIMESTAMP DEFAULT now();

ALTER TABLE vendor_transactions  ADD COLUMN created_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_at TIMESTAMP DEFAULT now();

ALTER TABLE director_draws       ADD COLUMN created_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_at TIMESTAMP DEFAULT now();

ALTER TABLE loans                ADD COLUMN created_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_at TIMESTAMP DEFAULT now();

ALTER TABLE recurring_bills      ADD COLUMN created_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_by INT REFERENCES users(user_id),
                                  ADD COLUMN updated_at TIMESTAMP DEFAULT now();

-- ============================================================
-- AUDIT LOG (row-level change history, independent of who's editing)
-- ============================================================

CREATE TABLE audit_log (
    audit_id        BIGSERIAL PRIMARY KEY,
    table_name      VARCHAR(50) NOT NULL,
                        -- No CHECK/FK constraining this to real table names, deliberately: the
                        -- valid set grows every time a new table gets an audit trigger, and a
                        -- CHECK here would need updating in lockstep or every write to that new
                        -- table would fail outright. This column should only ever be populated by
                        -- fn_audit_trigger (via TG_TABLE_NAME), never written to directly by
                        -- application code.
    record_id       INT NOT NULL,
    action          VARCHAR(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    changed_by      INT REFERENCES users(user_id),
    changed_at      TIMESTAMP DEFAULT now(),
    old_values      JSONB,
    new_values      JSONB
);

CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_changed_by ON audit_log(changed_by);

-- ============================================================
-- GENERIC AUDIT TRIGGER
-- Captures INSERT/UPDATE/DELETE on any table it's attached to.
-- app.current_user_id is set per request from your FastAPI session
-- (SET LOCAL app.current_user_id = '<id>' at the start of each transaction).
-- ============================================================

-- Takes the PK column name as a trigger argument (TG_ARGV[0]) so one
-- function works across tables with different PK column names
-- (entry_id, advance_id, transaction_id, draw_id, loan_id, ...).
CREATE OR REPLACE FUNCTION fn_audit_trigger() RETURNS TRIGGER AS $$
DECLARE
    v_user_id INT;
    v_pk_col  TEXT := TG_ARGV[0];
    v_record_id INT;
BEGIN
    BEGIN
        v_user_id := current_setting('app.current_user_id', true)::INT;
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    IF (TG_OP = 'DELETE') THEN
        v_record_id := (to_jsonb(OLD) ->> v_pk_col)::INT;
        INSERT INTO audit_log(table_name, record_id, action, changed_by, old_values)
        VALUES (TG_TABLE_NAME, v_record_id, TG_OP, v_user_id, to_jsonb(OLD));
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_record_id := (to_jsonb(NEW) ->> v_pk_col)::INT;
        INSERT INTO audit_log(table_name, record_id, action, changed_by, old_values, new_values)
        VALUES (TG_TABLE_NAME, v_record_id, TG_OP, v_user_id, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        v_record_id := (to_jsonb(NEW) ->> v_pk_col)::INT;
        INSERT INTO audit_log(table_name, record_id, action, changed_by, new_values)
        VALUES (TG_TABLE_NAME, v_record_id, TG_OP, v_user_id, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Attach to each financial table, passing its PK column name as the argument:

CREATE TRIGGER trg_audit_payroll_entries
AFTER INSERT OR UPDATE OR DELETE ON payroll_entries
FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('entry_id');

CREATE TRIGGER trg_audit_employee_advances
AFTER INSERT OR UPDATE OR DELETE ON employee_advances
FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('advance_id');

CREATE TRIGGER trg_audit_vendor_transactions
AFTER INSERT OR UPDATE OR DELETE ON vendor_transactions
FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('transaction_id');

CREATE TRIGGER trg_audit_director_draws
AFTER INSERT OR UPDATE OR DELETE ON director_draws
FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('draw_id');

CREATE TRIGGER trg_audit_loans
AFTER INSERT OR UPDATE OR DELETE ON loans
FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('loan_id');

CREATE TRIGGER trg_audit_recurring_bills
AFTER INSERT OR UPDATE OR DELETE ON recurring_bills
FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('recurring_bill_id');

-- ============================================================
-- POLYMORPHIC FK CHECK FOR loans.party_id
-- Postgres can't declare a real FK across three possible tables,
-- so this trigger enforces it manually before the row is written.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_validate_loan_party() RETURNS TRIGGER AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    IF NEW.party_type = 'employee' THEN
        SELECT EXISTS(SELECT 1 FROM employees WHERE employee_id = NEW.party_id) INTO v_exists;
    ELSIF NEW.party_type = 'director' THEN
        SELECT EXISTS(SELECT 1 FROM directors WHERE director_id = NEW.party_id) INTO v_exists;
    ELSIF NEW.party_type = 'vendor' THEN
        SELECT EXISTS(SELECT 1 FROM vendors WHERE vendor_id = NEW.party_id) INTO v_exists;
    ELSE
        RAISE EXCEPTION 'Unknown party_type: %', NEW.party_type;
    END IF;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'loans.party_id % does not exist in the % table', NEW.party_id, NEW.party_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_loan_party
BEFORE INSERT OR UPDATE ON loans
FOR EACH ROW EXECUTE FUNCTION fn_validate_loan_party();
