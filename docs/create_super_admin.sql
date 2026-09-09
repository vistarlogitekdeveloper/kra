-- Create a SUPER_ADMIN account directly in the database.
--
-- Needed because the API route that would do this (POST /employees) requires an
-- HR_ADMIN token, and every documented test account now returns 401 AUTH_001.
--
-- Verified against:
--   prisma/schema.prisma           model Employee  -> kra.employees
--   .../auth/auth.service.js:38    bcryptjs.compare(password, user.passwordHash)
--   .../employees.service.js:14    SALT_ROUNDS = 10
--   .../employees.repository.js:24 lazy kra."UserRole" enum widener
--
-- Login accepts EITHER the employee code OR the email
-- (auth.service.js:31 findUserByIdentifier), and rejects isActive = false.

--------------------------------------------------------------------------------
-- STEP 1 — widen the role enum.  RUN THIS ON ITS OWN, NOT IN A TRANSACTION.
--------------------------------------------------------------------------------
-- The app widens kra."UserRole" lazily at runtime and only BEST-EFFORT: it
-- swallows the error if the runtime DB user lacks ALTER TYPE. So SUPER_ADMIN may
-- not exist as an enum value yet, and step 2 would fail with
--   invalid input value for enum kra."UserRole": "SUPER_ADMIN"
-- Idempotent — safe to re-run.

ALTER TYPE kra."UserRole" ADD VALUE IF NOT EXISTS 'SUPER_ADMIN';

-- Confirm it took before continuing:
--   SELECT unnest(enum_range(NULL::kra."UserRole"));


--------------------------------------------------------------------------------
-- STEP 2 — create the account
--------------------------------------------------------------------------------
-- password_hash below is bcrypt cost 10 for:  Vistar@Super2026!
-- Generate your own instead (recommended) with:
--   cd D:\Vistar\vistar_CRM
--   node -e "console.log(require('bcryptjs').hashSync(process.argv[1],10))" "YourPassword"
--
-- organization_id is taken from the org that already has employees, so this
-- lands in the same tenant as your existing data instead of a guessed UUID.

INSERT INTO kra.employees (
  id,
  organization_id,
  email,
  password_hash,
  name,
  employee_code,
  position,
  department,
  role,
  auth_method,
  is_active,
  force_password_reset,
  joined_date,
  created_at,
  updated_at
)
SELECT
  gen_random_uuid(),
  (SELECT organization_id
     FROM kra.employees
    GROUP BY organization_id
    ORDER BY COUNT(*) DESC
    LIMIT 1),                                    -- busiest existing tenant
  'superadmin@vistar.test',
  '$2b$10$5aE8.IV/aMCP.Kq.FiMWcORbzSX5K.W2/JhaNhBqGzVJi9MZV0QCe',
  'Super Admin',
  'VLPL9001',                                    -- must match ^[A-Z]{2,5}[0-9]{4,8}$
  'Super Admin',
  'HR',
  'SUPER_ADMIN',
  'PASSWORD',
  TRUE,
  FALSE,                                         -- TRUE would force a reset on first login
  CURRENT_DATE,
  NOW(),
  NOW()
WHERE NOT EXISTS (                               -- idempotent: employee_code is UNIQUE
  SELECT 1 FROM kra.employees WHERE employee_code = 'VLPL9001'
);


--------------------------------------------------------------------------------
-- STEP 3 — verify
--------------------------------------------------------------------------------
SELECT id, employee_code, email, name, role, is_active,
       force_password_reset, organization_id
  FROM kra.employees
 WHERE employee_code = 'VLPL9001';

-- Expect exactly one row with role = SUPER_ADMIN and is_active = t.


--------------------------------------------------------------------------------
-- Optional — the multi-role column
--------------------------------------------------------------------------------
-- kra.employees also carries a lazily-added `roles` text[] used only via raw
-- SQL. Reads fall back to ARRAY[role] when it is null/empty, so you do NOT need
-- this. Run it only if the column already exists and you want it explicit:
--
--   UPDATE kra.employees
--      SET roles = ARRAY['SUPER_ADMIN']
--    WHERE employee_code = 'VLPL9001';


--------------------------------------------------------------------------------
-- If you ever need to undo
--------------------------------------------------------------------------------
--   DELETE FROM kra.employees WHERE employee_code = 'VLPL9001';
--
-- Safe only while the row has no dependent reviews/assignments. Prefer
-- deactivating instead, which the login path already honours:
--   UPDATE kra.employees SET is_active = FALSE WHERE employee_code = 'VLPL9001';
--
-- An enum value cannot be removed in Postgres. Step 1 is therefore permanent —
-- harmless, since a superset never invalidates existing rows.
