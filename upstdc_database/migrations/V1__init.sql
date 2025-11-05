-- ============================================================================
-- Flyway Migration: V1__init.sql
-- Purpose: Initialize PostgreSQL schema for UPSTDC Infrastructure Monitoring
-- Includes:
--   - Core RBAC: users, roles, permissions, user_roles, role_permissions
--   - Domain: projects, tenders, contractors, funds, milestones, project_progress,
--             inspections, handovers, payments, documents, audit_logs
--   - Constraints, foreign keys, indexes, identity columns, timestamps, soft delete
-- Notes:
--   - Designed for PostgreSQL 13+; uses GENERATED ALWAYS AS IDENTITY
--   - Geo fields (lat,lng) use numeric(10,7)/(10,7) to store up to ~1cm precision
--   - Soft delete pattern uses is_deleted boolean columns
--   - created_at/updated_at default to now(); updated_at should be maintained by application
--   - Compatible with DB server running on port 5001 (connection handled externally)
-- ============================================================================

-- Ensure required extensions (optional, kept minimal here)
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================
-- RBAC: roles
-- =========================
CREATE TABLE IF NOT EXISTS roles (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code            VARCHAR(50) NOT NULL UNIQUE,     -- e.g., ADMIN, OFFICER
    name            VARCHAR(100) NOT NULL,
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_roles_is_active ON roles (is_active);

-- =========================
-- RBAC: permissions
-- =========================
CREATE TABLE IF NOT EXISTS permissions (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code            VARCHAR(100) NOT NULL UNIQUE,    -- e.g., PROJECT_CREATE
    name            VARCHAR(150) NOT NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================
-- RBAC: users
-- =========================
CREATE TABLE IF NOT EXISTS users (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    phone           VARCHAR(25),
    password_hash   VARCHAR(255) NOT NULL,
    full_name       VARCHAR(150),
    designation     VARCHAR(150),
    department      VARCHAR(150),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_is_active ON users (is_active);
CREATE INDEX IF NOT EXISTS idx_users_is_deleted ON users (is_deleted);
CREATE INDEX IF NOT EXISTS idx_users_email_lower ON users (LOWER(email));

-- =========================
-- RBAC: user_roles (many-to-many)
-- =========================
CREATE TABLE IF NOT EXISTS user_roles (
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id     BIGINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles (role_id);

-- =========================
-- RBAC: role_permissions (many-to-many)
-- =========================
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id         BIGINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id   BIGINT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    granted_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role ON role_permissions (role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission ON role_permissions (permission_id);

-- =========================
-- Domain: contractors
-- =========================
CREATE TABLE IF NOT EXISTS contractors (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(200) NOT NULL,
    contact_person  VARCHAR(150),
    phone           VARCHAR(25),
    email           VARCHAR(255),
    address         TEXT,
    gstin           VARCHAR(20),
    pan             VARCHAR(15),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (LOWER(name))
);

CREATE INDEX IF NOT EXISTS idx_contractors_is_active ON contractors (is_active);
CREATE INDEX IF NOT EXISTS idx_contractors_is_deleted ON contractors (is_deleted);

-- =========================
-- Domain: projects
-- =========================
CREATE TABLE IF NOT EXISTS projects (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code            VARCHAR(100) UNIQUE,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    department      VARCHAR(150),
    start_date      DATE,
    end_date        DATE,
    budget_amount   NUMERIC(18,2),
    status          VARCHAR(50) NOT NULL DEFAULT 'PLANNED', -- PLANNED/ACTIVE/ON_HOLD/COMPLETED/CANCELLED
    owner_user_id   BIGINT REFERENCES users(id) ON DELETE SET NULL,
    lat             NUMERIC(10,7),
    lng             NUMERIC(10,7),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_projects_status ON projects (status);
CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects (owner_user_id);
CREATE INDEX IF NOT EXISTS idx_projects_deleted ON projects (is_deleted);
CREATE INDEX IF NOT EXISTS idx_projects_name_trgm ON projects (name);

-- =========================
-- Domain: tenders
-- =========================
CREATE TABLE IF NOT EXISTS tenders (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id          BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title               VARCHAR(255) NOT NULL,
    description         TEXT,
    publish_date        DATE,
    bid_open_date       DATE,
    bid_close_date      DATE,
    status              VARCHAR(50) NOT NULL DEFAULT 'OPEN', -- OPEN/CLOSED/AWARDED/CANCELLED
    awarded_contractor_id BIGINT REFERENCES contractors(id) ON DELETE SET NULL,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tenders_project ON tenders (project_id);
CREATE INDEX IF NOT EXISTS idx_tenders_status ON tenders (status);
CREATE INDEX IF NOT EXISTS idx_tenders_awarded_contractor ON tenders (awarded_contractor_id);
CREATE INDEX IF NOT EXISTS idx_tenders_deleted ON tenders (is_deleted);

-- =========================
-- Domain: funds (allocations and receipts related to project)
-- =========================
CREATE TABLE IF NOT EXISTS funds (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    allocation_ref  VARCHAR(100),
    amount          NUMERIC(18,2) NOT NULL,
    source          VARCHAR(150),
    received_on     DATE,
    notes           TEXT,
    created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_funds_project ON funds (project_id);
CREATE INDEX IF NOT EXISTS idx_funds_deleted ON funds (is_deleted);

-- =========================
-- Domain: milestones
-- =========================
CREATE TABLE IF NOT EXISTS milestones (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    due_date        DATE,
    weight_pct      NUMERIC(5,2), -- overall contribution to project progress
    status          VARCHAR(50) NOT NULL DEFAULT 'PENDING', -- PENDING/IN_PROGRESS/COMPLETED/DELAYED
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (project_id, LOWER(name))
);

CREATE INDEX IF NOT EXISTS idx_milestones_project ON milestones (project_id);
CREATE INDEX IF NOT EXISTS idx_milestones_status ON milestones (status);
CREATE INDEX IF NOT EXISTS idx_milestones_deleted ON milestones (is_deleted);

-- =========================
-- Domain: documents (polymorphic)
-- =========================
CREATE TABLE IF NOT EXISTS documents (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    path            TEXT NOT NULL,             -- storage path or URL
    mime_type       VARCHAR(150) NOT NULL,
    hash            VARCHAR(128),              -- checksum for integrity
    size            BIGINT,                    -- size in bytes
    owner_type      VARCHAR(50) NOT NULL,      -- e.g., 'PROJECT','TENDER','MILESTONE','PROGRESS','INSPECTION','HANDOVER','PAYMENT','USER','CONTRACTOR'
    owner_id        BIGINT NOT NULL,           -- references corresponding table id
    uploaded_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_owner ON documents (owner_type, owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_uploader ON documents (uploaded_by);
CREATE INDEX IF NOT EXISTS idx_documents_deleted ON documents (is_deleted);
CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents (hash);

-- =========================
-- Domain: project_progress (geo-tagged updates)
-- =========================
CREATE TABLE IF NOT EXISTS project_progress (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    milestone_id    BIGINT REFERENCES milestones(id) ON DELETE SET NULL,
    progress_pct    NUMERIC(5,2) NOT NULL CHECK (progress_pct >= 0 AND progress_pct <= 100),
    notes           TEXT,
    lat             NUMERIC(10,7),
    lng             NUMERIC(10,7),
    photo_id        BIGINT REFERENCES documents(id) ON DELETE SET NULL,
    created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_progress_project ON project_progress (project_id);
CREATE INDEX IF NOT EXISTS idx_progress_milestone ON project_progress (milestone_id);
CREATE INDEX IF NOT EXISTS idx_progress_created_by ON project_progress (created_by);
CREATE INDEX IF NOT EXISTS idx_progress_geo ON project_progress (lat, lng);
CREATE INDEX IF NOT EXISTS idx_progress_created_at ON project_progress (created_at DESC);

-- =========================
-- Domain: inspections
-- =========================
CREATE TABLE IF NOT EXISTS inspections (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    inspector_id    BIGINT REFERENCES users(id) ON DELETE SET NULL,
    title           VARCHAR(255) NOT NULL,
    notes           TEXT,
    lat             NUMERIC(10,7),
    lng             NUMERIC(10,7),
    status          VARCHAR(50) NOT NULL DEFAULT 'SCHEDULED', -- SCHEDULED/IN_PROGRESS/COMPLETED/ISSUE_FOUND/CLOSED
    scheduled_at    TIMESTAMPTZ,
    inspected_at    TIMESTAMPTZ,
    report_doc_id   BIGINT REFERENCES documents(id) ON DELETE SET NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inspections_project ON inspections (project_id);
CREATE INDEX IF NOT EXISTS idx_inspections_inspector ON inspections (inspector_id);
CREATE INDEX IF NOT EXISTS idx_inspections_status ON inspections (status);
CREATE INDEX IF NOT EXISTS idx_inspections_deleted ON inspections (is_deleted);
CREATE INDEX IF NOT EXISTS idx_inspections_geo ON inspections (lat, lng);

-- =========================
-- Domain: handovers
-- =========================
CREATE TABLE IF NOT EXISTS handovers (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    handover_date   DATE,
    accepted_by     VARCHAR(150),
    document_id     BIGINT REFERENCES documents(id) ON DELETE SET NULL,
    created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_handovers_project ON handovers (project_id);
CREATE INDEX IF NOT EXISTS idx_handovers_deleted ON handovers (is_deleted);

-- =========================
-- Domain: payments
-- =========================
CREATE TABLE IF NOT EXISTS payments (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    contractor_id   BIGINT REFERENCES contractors(id) ON DELETE SET NULL,
    milestone_id    BIGINT REFERENCES milestones(id) ON DELETE SET NULL,
    amount          NUMERIC(18,2) NOT NULL CHECK (amount >= 0),
    status          VARCHAR(50) NOT NULL DEFAULT 'PENDING', -- PENDING/APPROVED/RELEASED/REJECTED
    reference_no    VARCHAR(100),
    paid_on         DATE,
    notes           TEXT,
    document_id     BIGINT REFERENCES documents(id) ON DELETE SET NULL,
    created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_project ON payments (project_id);
CREATE INDEX IF NOT EXISTS idx_payments_contractor ON payments (contractor_id);
CREATE INDEX IF NOT EXISTS idx_payments_milestone ON payments (milestone_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments (status);
CREATE INDEX IF NOT EXISTS idx_payments_deleted ON payments (is_deleted);

-- =========================
-- Domain: audit_logs
-- =========================
CREATE TABLE IF NOT EXISTS audit_logs (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id   BIGINT REFERENCES users(id) ON DELETE SET NULL,
    action          VARCHAR(100) NOT NULL,         -- e.g., LOGIN, CREATE_PROJECT
    entity_type     VARCHAR(50),                   -- e.g., PROJECT, USER
    entity_id       BIGINT,
    details         JSONB,                         -- arbitrary details
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_logs (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs (action);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs (created_at DESC);

-- =========================
-- Consistency constraints and helpful checks
-- =========================

-- Payments reference_no uniqueness per project
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_project_reference
    ON payments (project_id, reference_no)
    WHERE reference_no IS NOT NULL;

-- Documents owner integrity is handled at application layer since polymorphic
-- Optionally, enforce owner_type domains
ALTER TABLE documents
    ADD CONSTRAINT documents_owner_type_chk
    CHECK (owner_type IN (
        'PROJECT','TENDER','MILESTONE','PROGRESS','INSPECTION','HANDOVER','PAYMENT','USER','CONTRACTOR'
    ));

-- Basic project status domain
ALTER TABLE projects
    ADD CONSTRAINT projects_status_chk
    CHECK (status IN ('PLANNED','ACTIVE','ON_HOLD','COMPLETED','CANCELLED'));

-- Tender status domain
ALTER TABLE tenders
    ADD CONSTRAINT tenders_status_chk
    CHECK (status IN ('OPEN','CLOSED','AWARDED','CANCELLED'));

-- Milestone status domain
ALTER TABLE milestones
    ADD CONSTRAINT milestones_status_chk
    CHECK (status IN ('PENDING','IN_PROGRESS','COMPLETED','DELAYED'));

-- Inspection status domain
ALTER TABLE inspections
    ADD CONSTRAINT inspections_status_chk
    CHECK (status IN ('SCHEDULED','IN_PROGRESS','COMPLETED','ISSUE_FOUND','CLOSED'));

-- Payments status domain
ALTER TABLE payments
    ADD CONSTRAINT payments_status_chk
    CHECK (status IN ('PENDING','APPROVED','RELEASED','REJECTED'));
