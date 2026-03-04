-- ============================================================
-- THE MARTA ENGINE — Supabase Schema
-- US Cargo Brokers Command Center
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- ENUM TYPES
-- ============================================================

CREATE TYPE entry_domain AS ENUM (
  'legal',
  'financial',
  'operations',
  'hr',
  'personal',
  'general'
);

CREATE TYPE entry_priority AS ENUM (
  'critical',
  'high',
  'medium',
  'low'
);

CREATE TYPE task_status AS ENUM (
  'pending',
  'in_progress',
  'blocked',
  'completed',
  'cancelled'
);

CREATE TYPE legal_case_type AS ENUM (
  'custody',
  'contract',
  'cease_desist',
  'bond_claim',
  'other'
);

CREATE TYPE financial_flag_type AS ENUM (
  'duplicate_payment',
  'bond_claim',
  'billing_dispute',
  'reconciliation',
  'audit_finding'
);

-- ============================================================
-- 1. QUICK CAPTURE — Universal Intake Log
--    Replaces: manual note-taking, context switching,
--    scattered data entry across tools
-- ============================================================

CREATE TABLE entries (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID REFERENCES auth.users(id) NOT NULL,
  content       TEXT NOT NULL,
  domain        entry_domain DEFAULT 'general',
  priority      entry_priority DEFAULT 'medium',
  tags          TEXT[] DEFAULT '{}',
  is_actionable BOOLEAN DEFAULT FALSE,
  resolved      BOOLEAN DEFAULT FALSE,
  resolved_at   TIMESTAMPTZ,
  metadata      JSONB DEFAULT '{}',
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_entries_user ON entries(user_id);
CREATE INDEX idx_entries_domain ON entries(domain);
CREATE INDEX idx_entries_created ON entries(created_at DESC);
CREATE INDEX idx_entries_priority ON entries(priority);

-- ============================================================
-- 2. LEGAL TRACKER
--    Replaces: manual case tracking, missed deadlines,
--    attorney communication gaps
-- ============================================================

CREATE TABLE legal_matters (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  case_name       TEXT NOT NULL,
  case_type       legal_case_type NOT NULL,
  case_number     TEXT,
  court           TEXT,
  judge           TEXT,
  attorney_name   TEXT,
  attorney_email  TEXT,
  opposing_counsel TEXT,
  status          task_status DEFAULT 'in_progress',
  notes           TEXT,
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE legal_deadlines (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  matter_id       UUID REFERENCES legal_matters(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  title           TEXT NOT NULL,
  description     TEXT,
  deadline_date   TIMESTAMPTZ NOT NULL,
  reminder_days   INT DEFAULT 3,
  completed       BOOLEAN DEFAULT FALSE,
  completed_at    TIMESTAMPTZ,
  priority        entry_priority DEFAULT 'high',
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_deadlines_date ON legal_deadlines(deadline_date);
CREATE INDEX idx_deadlines_matter ON legal_deadlines(matter_id);

CREATE TABLE legal_communications (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  matter_id       UUID REFERENCES legal_matters(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  from_party      TEXT NOT NULL,
  to_party        TEXT NOT NULL,
  subject         TEXT,
  summary         TEXT NOT NULL,
  was_copied      BOOLEAN DEFAULT TRUE,  -- Track if Adam was CC'd
  communication_date TIMESTAMPTZ DEFAULT NOW(),
  flagged         BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. FINANCIAL CONTROLS
--    Replaces: manual QB-TMS reconciliation, scattered
--    bond claim tracking, duplicate payment hunting
-- ============================================================

CREATE TABLE financial_flags (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  flag_type       financial_flag_type NOT NULL,
  title           TEXT NOT NULL,
  description     TEXT,
  amount          DECIMAL(12, 2),
  vendor          TEXT,
  reference_number TEXT,
  source_system   TEXT,  -- 'quickbooks', 'tms', 'manual'
  status          task_status DEFAULT 'pending',
  resolved_at     TIMESTAMPTZ,
  resolution_notes TEXT,
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_flags_type ON financial_flags(flag_type);
CREATE INDEX idx_flags_status ON financial_flags(status);
CREATE INDEX idx_flags_amount ON financial_flags(amount DESC);

-- ============================================================
-- 4. HR / EMPLOYEE MANAGEMENT
--    Replaces: manual onboarding checklists, scattered
--    employee documentation
-- ============================================================

CREATE TABLE employees (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  full_name       TEXT NOT NULL,
  role            TEXT,
  email           TEXT,
  phone           TEXT,
  start_date      DATE,
  end_date        DATE,
  is_active       BOOLEAN DEFAULT TRUE,
  onboarding_complete BOOLEAN DEFAULT FALSE,
  notes           TEXT,
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE onboarding_tasks (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id     UUID REFERENCES employees(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  task_name       TEXT NOT NULL,
  description     TEXT,
  completed       BOOLEAN DEFAULT FALSE,
  completed_at    TIMESTAMPTZ,
  due_date        DATE,
  sort_order      INT DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. UNIFIED TASK BOARD
--    Cross-domain task management
-- ============================================================

CREATE TABLE tasks (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  title           TEXT NOT NULL,
  description     TEXT,
  domain          entry_domain DEFAULT 'general',
  priority        entry_priority DEFAULT 'medium',
  status          task_status DEFAULT 'pending',
  due_date        TIMESTAMPTZ,
  linked_entry_id UUID REFERENCES entries(id),
  linked_matter_id UUID REFERENCES legal_matters(id),
  linked_flag_id  UUID REFERENCES financial_flags(id),
  tags            TEXT[] DEFAULT '{}',
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_domain ON tasks(domain);
CREATE INDEX idx_tasks_due ON tasks(due_date);

-- ============================================================
-- 6. AI INSIGHTS — Proactive Suggestions
--    Stores Claude API analysis outputs
-- ============================================================

CREATE TABLE ai_insights (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  domain          entry_domain,
  insight_type    TEXT NOT NULL,  -- 'deadline_warning', 'pattern', 'suggestion', 'anomaly'
  title           TEXT NOT NULL,
  content         TEXT NOT NULL,
  severity        entry_priority DEFAULT 'medium',
  acknowledged    BOOLEAN DEFAULT FALSE,
  acknowledged_at TIMESTAMPTZ,
  source_ids      UUID[] DEFAULT '{}',  -- references to entries/tasks that triggered this
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_insights_ack ON ai_insights(acknowledged);
CREATE INDEX idx_insights_severity ON ai_insights(severity);

-- ============================================================
-- 7. ACTIVITY LOG — Full Audit Trail
-- ============================================================

CREATE TABLE activity_log (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) NOT NULL,
  action          TEXT NOT NULL,
  table_name      TEXT NOT NULL,
  record_id       UUID,
  details         JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_activity_user ON activity_log(user_id, created_at DESC);

-- ============================================================
-- ROW-LEVEL SECURITY POLICIES
-- Every table locked to authenticated user's own data
-- ============================================================

ALTER TABLE entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_matters ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_communications ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

-- Generic policy generator: user can only CRUD their own rows
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'entries', 'legal_matters', 'legal_deadlines',
    'legal_communications', 'financial_flags', 'employees',
    'onboarding_tasks', 'tasks', 'ai_insights', 'activity_log'
  ]
  LOOP
    EXECUTE format(
      'CREATE POLICY "Users manage own %1$s" ON %1$s
         FOR ALL
         USING (auth.uid() = user_id)
         WITH CHECK (auth.uid() = user_id)',
      t
    );
  END LOOP;
END $$;

-- Service role bypass for Edge Functions (AI insights writer)
CREATE POLICY "Service role inserts insights"
  ON ai_insights FOR INSERT
  WITH CHECK (true);

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables with updated_at
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'entries', 'legal_matters', 'financial_flags',
    'employees', 'tasks'
  ]
  LOOP
    EXECUTE format(
      'CREATE TRIGGER set_%1$s_updated
         BEFORE UPDATE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION update_modified_column()',
      t
    );
  END LOOP;
END $$;

-- Activity logging function
CREATE OR REPLACE FUNCTION log_activity()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO activity_log (user_id, action, table_name, record_id, details)
  VALUES (
    COALESCE(NEW.user_id, OLD.user_id),
    TG_OP,
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    jsonb_build_object(
      'operation', TG_OP,
      'timestamp', NOW()
    )
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply activity logging to key tables
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['entries', 'tasks', 'financial_flags', 'legal_matters']
  LOOP
    EXECUTE format(
      'CREATE TRIGGER log_%1$s_activity
         AFTER INSERT OR UPDATE OR DELETE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION log_activity()',
      t
    );
  END LOOP;
END $$;

-- ============================================================
-- VIEWS — Dashboard Aggregations
-- ============================================================

CREATE OR REPLACE VIEW dashboard_summary AS
SELECT
  u.id AS user_id,
  (SELECT COUNT(*) FROM entries e WHERE e.user_id = u.id AND e.resolved = FALSE) AS open_entries,
  (SELECT COUNT(*) FROM tasks t WHERE t.user_id = u.id AND t.status IN ('pending', 'in_progress')) AS active_tasks,
  (SELECT COUNT(*) FROM tasks t WHERE t.user_id = u.id AND t.status = 'pending' AND t.priority = 'critical') AS critical_tasks,
  (SELECT COUNT(*) FROM legal_deadlines ld WHERE ld.user_id = u.id AND ld.completed = FALSE AND ld.deadline_date <= NOW() + INTERVAL '7 days') AS upcoming_deadlines,
  (SELECT COUNT(*) FROM financial_flags ff WHERE ff.user_id = u.id AND ff.status = 'pending') AS open_flags,
  (SELECT COALESCE(SUM(ff.amount), 0) FROM financial_flags ff WHERE ff.user_id = u.id AND ff.status = 'pending') AS flagged_amount,
  (SELECT COUNT(*) FROM ai_insights ai WHERE ai.user_id = u.id AND ai.acknowledged = FALSE) AS unread_insights,
  (SELECT COUNT(*) FROM employees emp WHERE emp.user_id = u.id AND emp.is_active = TRUE) AS active_employees
FROM auth.users u;
