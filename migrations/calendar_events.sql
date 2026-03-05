-- ================================================================
-- CALENDAR EVENTS TABLE
-- Kono Paddock V2 — Calendar Module
-- ================================================================

CREATE TABLE IF NOT EXISTS calendar_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  event_date  DATE NOT NULL,
  event_time  TIME,
  event_type  TEXT NOT NULL DEFAULT 'task'
              CHECK (event_type IN ('deadline','court_date','exchange','task','meeting','flag')),
  domain      TEXT NOT NULL DEFAULT 'general'
              CHECK (domain IN ('legal','financial','operations','hr','personal','general')),
  description TEXT,
  source      TEXT,            -- e.g. 'manual', 'legal_deadline', 'task'
  repeat_rule TEXT,            -- e.g. 'weekly', 'biweekly', 'monthly', null
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_calendar_events_user    ON calendar_events (user_id);
CREATE INDEX idx_calendar_events_date    ON calendar_events (event_date);
CREATE INDEX idx_calendar_events_user_dt ON calendar_events (user_id, event_date);

-- RLS
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own calendar events"
  ON calendar_events FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own calendar events"
  ON calendar_events FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own calendar events"
  ON calendar_events FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own calendar events"
  ON calendar_events FOR DELETE
  USING (auth.uid() = user_id);
