-- ============================================================================
-- Update is_upcoming Logic When Events Are Activated
-- ============================================================================
--
-- Requirement: When an event is activated (is_active = true), it should no
-- longer be marked as is_upcoming. The NEXT upcoming event should get is_upcoming = true.
--
-- Run this in your Supabase SQL Editor AFTER running SUPABASE_FIX_IS_UPCOMING_CORRECTED.sql
-- ============================================================================

-- Update the recalculate_is_upcoming function to exclude active events
CREATE OR REPLACE FUNCTION recalculate_is_upcoming(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_most_upcoming_id UUID;
BEGIN
  -- Find the most upcoming event for this user
  -- EXCLUDES active events - active events are not "upcoming" anymore!
  SELECT id INTO v_most_upcoming_id
  FROM events
  WHERE user_id = p_user_id
    AND is_active = false  -- ✅ NEW: Exclude active events
    AND (
      -- Event has end_time: check if end hasn't passed
      (end_time IS NOT NULL AND (event_date + end_time::time) >= NOW())
      OR
      -- Event has no end_time: check if date hasn't passed
      (end_time IS NULL AND event_date >= CURRENT_DATE)
    )
  ORDER BY
    event_date ASC,
    COALESCE(start_time, '00:00:00'::time) ASC
  LIMIT 1;

  -- Set ALL events for this user to is_upcoming = false
  UPDATE events
  SET is_upcoming = false
  WHERE user_id = p_user_id;

  -- Set ONLY the most upcoming event to is_upcoming = true
  IF v_most_upcoming_id IS NOT NULL THEN
    UPDATE events
    SET is_upcoming = true
    WHERE id = v_most_upcoming_id;
  END IF;
END;
$$;

-- The triggers are already in place from the previous migration
-- They will automatically use this updated function

-- ============================================================================
-- Test the fix
-- ============================================================================
-- Run this to recalculate is_upcoming for all users with the new logic:

DO $$
DECLARE
  user_rec RECORD;
BEGIN
  FOR user_rec IN SELECT DISTINCT user_id FROM events LOOP
    PERFORM recalculate_is_upcoming(user_rec.user_id);
  END LOOP;
END;
$$;

-- ============================================================================
-- Verify
-- ============================================================================
-- After running, verify that:
-- 1. Active events have is_upcoming = false
-- 2. Only ONE non-active event per user has is_upcoming = true
--
-- SELECT
--   name,
--   event_date,
--   is_active,
--   is_upcoming
-- FROM events
-- ORDER BY event_date ASC;
-- ============================================================================
