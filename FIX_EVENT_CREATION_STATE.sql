-- ============================================================================
-- FIX EVENT CREATION STATE
-- ============================================================================
-- This migration ensures that when a new event is created, the is_upcoming
-- field is properly set across all events for the user.
--
-- Problem: When creating a new event, it gets is_active=false, is_ended=false
-- but is_upcoming is not calculated, causing filtering issues.
--
-- Solution: Add a trigger that recalculates is_upcoming after INSERT
-- ============================================================================

-- ============================================================================
-- STEP 1: Create function to recalculate is_upcoming for a user
-- ============================================================================

CREATE OR REPLACE FUNCTION recalculate_upcoming_event(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_next_upcoming_id UUID;
BEGIN
  -- Clear is_upcoming for ALL events for this user
  UPDATE events
  SET is_upcoming = false
  WHERE user_id = p_user_id;

  -- Find the NEXT upcoming event
  -- Logic: Earliest event with is_ended = false and is_active = false
  SELECT id INTO v_next_upcoming_id
  FROM events
  WHERE user_id = p_user_id
    AND is_ended = false
    AND is_active = false
    AND (
      -- If event has end_time, check if it hasn't passed (use > not >=)
      (end_time IS NOT NULL AND
       (event_date || ' ' || end_time::TEXT)::TIMESTAMP > NOW()) OR
      -- If no end_time, check if date is today or future
      (end_time IS NULL AND event_date >= CURRENT_DATE)
    )
  ORDER BY
    event_date ASC,
    COALESCE(start_time, '00:00:00'::TIME) ASC
  LIMIT 1;

  -- Set is_upcoming = true for ONLY the next upcoming event
  IF v_next_upcoming_id IS NOT NULL THEN
    UPDATE events
    SET is_upcoming = true,
        updated_at = NOW()
    WHERE id = v_next_upcoming_id;

    RAISE NOTICE 'Set is_upcoming=true for event %', v_next_upcoming_id;
  ELSE
    RAISE NOTICE 'No upcoming events found for user %', p_user_id;
  END IF;
END;
$$;

-- ============================================================================
-- STEP 2: Create trigger function for after INSERT
-- ============================================================================

CREATE OR REPLACE FUNCTION after_event_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Recalculate is_upcoming for this user after inserting a new event
  PERFORM recalculate_upcoming_event(NEW.user_id);
  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 3: Create trigger on events table
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_after_event_insert ON events;

CREATE TRIGGER trigger_after_event_insert
  AFTER INSERT ON events
  FOR EACH ROW
  EXECUTE FUNCTION after_event_insert();

-- ============================================================================
-- STEP 4: Fix existing events (run recalculate for all users)
-- ============================================================================

DO $$
DECLARE
  v_user_id UUID;
BEGIN
  RAISE NOTICE 'Recalculating is_upcoming for all users...';

  FOR v_user_id IN
    SELECT DISTINCT user_id FROM events
  LOOP
    PERFORM recalculate_upcoming_event(v_user_id);
  END LOOP;

  RAISE NOTICE 'Recalculation complete!';
END $$;

-- ============================================================================
-- STEP 5: Verify the results
-- ============================================================================

SELECT
  user_id,
  id,
  name,
  event_date,
  is_active,
  is_upcoming,
  is_ended,
  CASE
    WHEN is_active THEN '← ACTIVE'
    WHEN is_upcoming THEN '← MOST UPCOMING'
    WHEN is_ended THEN '← ENDED'
    ELSE '← WAITING'
  END as status
FROM events
ORDER BY user_id, event_date ASC;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
-- This ensures:
-- 1. New events trigger is_upcoming recalculation
-- 2. Only ONE event per user has is_upcoming = true
-- 3. Events show correctly in the UI as "upcoming" vs "ended"
-- ============================================================================
