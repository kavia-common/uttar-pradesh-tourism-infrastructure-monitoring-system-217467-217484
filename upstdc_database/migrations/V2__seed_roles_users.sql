-- ============================================================================
-- Flyway Migration: V2__seed_roles_users.sql
-- Purpose: Seed base roles, a minimal permission set, role-permission mappings,
--          and a default ADMIN user with a placeholder bcrypt password hash.
-- Notes:
--   - The ADMIN user's password_hash is set to the literal string:
--       'ADMIN_PASSWORD_HASH'
--     The backend should replace this with a real bcrypt hash on first run.
--   - This migration is idempotent by using ON CONFLICT DO NOTHING where possible.
-- ============================================================================

-- Seed Roles
INSERT INTO roles (code, name, description)
VALUES
    ('ADMIN',      'Administrator', 'Full system administration'),
    ('OFFICER',    'Officer',       'Department/Division officer'),
    ('ENGINEER',   'Engineer',      'Project engineer'),
    ('CONTRACTOR', 'Contractor',    'External contractor partner'),
    ('AUDITOR',    'Auditor',       'Audit and compliance')
ON CONFLICT (code) DO NOTHING;

-- Seed minimal Permissions (extend later as needed)
INSERT INTO permissions (code, name, description)
VALUES
    ('USER_MANAGE',         'Manage Users',                'Create, update, deactivate users'),
    ('PROJECT_CREATE',      'Create Projects',             'Create new projects'),
    ('PROJECT_VIEW',        'View Projects',               'Read-only access to projects'),
    ('PROJECT_EDIT',        'Edit Projects',               'Update project details'),
    ('TENDER_MANAGE',       'Manage Tenders',              'Create and manage tenders'),
    ('CONTRACTOR_MANAGE',   'Manage Contractors',          'Create and manage contractors'),
    ('PROGRESS_UPDATE',     'Update Progress',             'Submit project progress'),
    ('PAYMENT_MANAGE',      'Manage Payments',             'Create and approve payments'),
    ('DOCUMENT_UPLOAD',     'Upload Documents',            'Upload files and attachments'),
    ('AUDIT_VIEW',          'View Audit Logs',             'Read audit and activity logs')
ON CONFLICT (code) DO NOTHING;

-- Fetch role IDs
WITH r AS (
    SELECT code, id FROM roles WHERE code IN ('ADMIN','OFFICER','ENGINEER','CONTRACTOR','AUDITOR')
),
p AS (
    SELECT code, id FROM permissions
)
-- Map ADMIN to all permissions
INSERT INTO role_permissions (role_id, permission_id, granted_by)
SELECT r_admin.id, p_all.id, NULL
FROM r r_admin
JOIN p p_all ON 1=1
WHERE r_admin.code = 'ADMIN'
ON CONFLICT DO NOTHING;

-- Map OFFICER to key permissions
INSERT INTO role_permissions (role_id, permission_id, granted_by)
SELECT r_officer.id, p_needed.id, NULL
FROM (SELECT id FROM roles WHERE code = 'OFFICER') r_officer(id)
JOIN (
    SELECT id FROM permissions WHERE code IN ('PROJECT_CREATE','PROJECT_VIEW','PROJECT_EDIT','TENDER_MANAGE','CONTRACTOR_MANAGE','DOCUMENT_UPLOAD','PAYMENT_MANAGE')
) p_needed ON 1=1
ON CONFLICT DO NOTHING;

-- Map ENGINEER to progress and project view/edit
INSERT INTO role_permissions (role_id, permission_id, granted_by)
SELECT r_engineer.id, p_needed.id, NULL
FROM (SELECT id FROM roles WHERE code = 'ENGINEER') r_engineer(id)
JOIN (
    SELECT id FROM permissions WHERE code IN ('PROJECT_VIEW','PROJECT_EDIT','PROGRESS_UPDATE','DOCUMENT_UPLOAD')
) p_needed ON 1=1
ON CONFLICT DO NOTHING;

-- Map CONTRACTOR to progress and document upload (limited)
INSERT INTO role_permissions (role_id, permission_id, granted_by)
SELECT r_contractor.id, p_needed.id, NULL
FROM (SELECT id FROM roles WHERE code = 'CONTRACTOR') r_contractor(id)
JOIN (
    SELECT id FROM permissions WHERE code IN ('PROJECT_VIEW','PROGRESS_UPDATE','DOCUMENT_UPLOAD')
) p_needed ON 1=1
ON CONFLICT DO NOTHING;

-- Map AUDITOR to read-only and audit view
INSERT INTO role_permissions (role_id, permission_id, granted_by)
SELECT r_auditor.id, p_needed.id, NULL
FROM (SELECT id FROM roles WHERE code = 'AUDITOR') r_auditor(id)
JOIN (
    SELECT id FROM permissions WHERE code IN ('PROJECT_VIEW','AUDIT_VIEW')
) p_needed ON 1=1
ON CONFLICT DO NOTHING;

-- Seed default admin user
-- NOTE: password_hash is intentionally a placeholder string. Replace on first login.
INSERT INTO users (email, phone, password_hash, full_name, designation, department, is_active, is_deleted)
VALUES ('admin@upstdc.in', NULL, 'ADMIN_PASSWORD_HASH', 'System Administrator', 'Administrator', 'UPSTDC', TRUE, FALSE)
ON CONFLICT (email) DO NOTHING;

-- Assign ADMIN role to default admin
INSERT INTO user_roles (user_id, role_id, assigned_at, assigned_by)
SELECT u.id, r.id, NOW(), NULL
FROM users u
JOIN roles r ON r.code = 'ADMIN'
WHERE u.email = 'admin@upstdc.in'
ON CONFLICT DO NOTHING;
