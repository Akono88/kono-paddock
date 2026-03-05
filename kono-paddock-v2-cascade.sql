-- ============================================================
-- THE KONO PADDOCK V2 — CASCADE TRIGGER
-- Auto-creates downstream objects from guided intake entries
-- ============================================================

-- Drop existing trigger if upgrading
DROP TRIGGER IF EXISTS entry_cascade ON entries;
DROP FUNCTION IF EXISTS cascade_entry_actions();

CREATE OR REPLACE FUNCTION cascade_entry_actions()
RETURNS TRIGGER AS $$
BEGIN
  -- ── AUTO-CREATE TASK ──────────────────────────────────────
  -- When guided intake includes a "next_action" and entry is actionable
  IF NEW.metadata->>'next_action' IS NOT NULL 
     AND NEW.is_actionable = TRUE THEN
    INSERT INTO tasks (
      user_id, title, description, domain, priority, 
      status, linked_entry_id, tags
    ) VALUES (
      NEW.user_id, 
      NEW.metadata->>'next_action', 
      NEW.content, 
      NEW.domain, 
      NEW.priority, 
      'pending', 
      NEW.id, 
      NEW.tags
    );
  END IF;

  -- ── AUTO-CREATE FINANCIAL FLAG ────────────────────────────
  -- When entry contains flag_type and amount metadata
  IF NEW.metadata->>'flag_type' IS NOT NULL 
     AND NEW.metadata->>'amount' IS NOT NULL THEN
    INSERT INTO financial_flags (
      user_id, flag_type, title, amount, source_system, status
    ) VALUES (
      NEW.user_id,
      (NEW.metadata->>'flag_type')::financial_flag_type,
      LEFT(NEW.content, 120),
      (regexp_replace(NEW.metadata->>'amount', '[$,]', '', 'g'))::decimal,
      'paddock-intake',
      'pending'
    );
  END IF;

  -- ── AUTO-FLAG CC VIOLATION ────────────────────────────────
  -- When legal entry includes cc_flag = true (Janes Protocol)
  IF (NEW.metadata->>'cc_flag')::boolean = TRUE THEN
    INSERT INTO legal_communications (
      user_id, from_party, to_party, subject, 
      summary, was_copied, flagged, communication_date
    ) VALUES (
      NEW.user_id,
      COALESCE(NEW.metadata->>'from_party', 'Opposing Counsel'),
      COALESCE(NEW.metadata->>'to_party', 'Attorney'),
      COALESCE(NEW.metadata->>'comm_subject', 'CC Violation — Auto-flagged'),
      NEW.content,
      FALSE,
      TRUE,
      NOW()
    );
  END IF;

  -- ── AUTO-CREATE LEGAL DEADLINE ────────────────────────────
  -- When entry contains a deadline_hint in metadata
  -- Stores as a reminder; user refines the date in Legal Tracker
  IF NEW.metadata->>'deadline_hint' IS NOT NULL 
     AND NEW.domain = 'legal' THEN
    INSERT INTO legal_deadlines (
      user_id, title, description, deadline_date, 
      priority, completed
    ) VALUES (
      NEW.user_id,
      COALESCE(NEW.metadata->>'next_action', LEFT(NEW.content, 80)),
      NEW.content,
      -- Parse relative dates; default to 7 days if unparseable
      CASE 
        WHEN NEW.metadata->>'deadline_hint' ~* 'today' THEN NOW()
        WHEN NEW.metadata->>'deadline_hint' ~* 'tomorrow' THEN NOW() + INTERVAL '1 day'
        WHEN NEW.metadata->>'deadline_hint' ~* 'friday' THEN 
          NOW() + ((5 - EXTRACT(DOW FROM NOW()) + 7)::int % 7) * INTERVAL '1 day'
        WHEN NEW.metadata->>'deadline_hint' ~* 'eow|end of week' THEN
          NOW() + ((5 - EXTRACT(DOW FROM NOW()) + 7)::int % 7) * INTERVAL '1 day'
        WHEN NEW.metadata->>'deadline_hint' ~* 'eod|end of day' THEN
          DATE_TRUNC('day', NOW()) + INTERVAL '17 hours'
        WHEN NEW.metadata->>'deadline_hint' ~* '(\d+)\s*days?' THEN
          NOW() + (SUBSTRING(NEW.metadata->>'deadline_hint' FROM '(\d+)')::int * INTERVAL '1 day')
        ELSE NOW() + INTERVAL '7 days'
      END,
      NEW.priority,
      FALSE
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach to entries table
CREATE TRIGGER entry_cascade
  AFTER INSERT ON entries
  FOR EACH ROW EXECUTE FUNCTION cascade_entry_actions();

-- ============================================================
-- VERIFICATION QUERY
-- After running, test with:
-- INSERT INTO entries (user_id, content, domain, priority, is_actionable, metadata)
-- VALUES (
--   '014ddd84-9083-4597-b5c4-7ee613f7c428',
--   'Wolfe needs discovery response reviewed — deadline Friday. Nicole Janes NOT cc''d on motion.',
--   'legal', 'high', true,
--   '{"next_action": "Review discovery response and send to Wolfe", 
--     "deadline_hint": "Friday", 
--     "cc_flag": true,
--     "from_party": "Nicole Janes",
--     "to_party": "Mr. Wolfe"}'::jsonb
-- );
-- Then check: SELECT * FROM tasks ORDER BY created_at DESC LIMIT 1;
--             SELECT * FROM legal_deadlines ORDER BY created_at DESC LIMIT 1;
--             SELECT * FROM legal_communications ORDER BY created_at DESC LIMIT 1;
-- ============================================================
