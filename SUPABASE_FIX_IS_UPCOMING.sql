-- ============================================================================
-- Fix is_upcoming Column to Only Mark ONE Event Per User
-- ============================================================================
--
-- Problem: All future events have is_upcoming = true
-- Solution: Only the SINGLE most upcoming event should have is_upcoming = true
--
-- Run this in your Supabase SQL Editor
-- ============================================================================

-- Step 1: Create a function to recalculate is_upcoming for a user's events
CREATE OR REPLACE FUNCTION recalculate_is_upcoming(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_most_upcoming_id UUID;
BEGIN
  -- Find the most upcoming event for this user
  -- (closest to now that hasn't ended yet)
  SELECT id INTO v_most_upcoming_id
  FROM events
  WHERE user_id = p_user_id
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

-- Step 2: Create a trigger function to recalculate after insert/update
CREATE OR REPLACE FUNCTION trigger_recalculate_is_upcoming()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Recalculate for the affected user
  PERFORM recalculate_is_upcoming(NEW.user_id);

  -- If user_id changed (unlikely but handle it), recalculate for old user too
  IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM NEW.user_id THEN
    PERFORM recalculate_is_upcoming(OLD.user_id);
  END IF;

  RETURN NEW;
END;
$$;

-- Step 3: Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_events_is_upcoming ON events;

-- Step 4: Create the trigger
-- Fires after INSERT or UPDATE of date/time columns
CREATE TRIGGER trigger_events_is_upcoming
AFTER INSERT OR UPDATE OF event_date, start_time, end_time, is_active ON events
FOR EACH ROW
EXECUTE FUNCTION trigger_recalculate_is_upcoming();

-- Step 5: Also recalculate when events are deleted
CREATE OR REPLACE FUNCTION trigger_recalculate_is_upcoming_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM recalculate_is_upcoming(OLD.user_id);
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trigger_events_is_upcoming_on_delete ON events;

CREATE TRIGGER trigger_events_is_upcoming_on_delete
AFTER DELETE ON events
FOR EACH ROW
EXECUTE FUNCTION trigger_recalculate_is_upcoming_on_delete();

-- Step 6: Recalculate is_upcoming for ALL existing events
-- This fixes any existing data
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
-- Verification Queries
-- ============================================================================
-- Run these to verify the fix worked:

-- Check how many events per user have is_upcoming = true (should be 0 or 1)
-- SELECT user_id, COUNT(*) as upcoming_count
-- FROM events
-- WHERE is_upcoming = true
-- GROUP BY user_id;

-- See all your events with their is_upcoming status
-- SELECT
--   name,
--   event_date,
--   start_time,
--   end_time,
--   is_active,
--   is_upcoming
-- FROM events
-- WHERE user_id = 'YOUR_USER_ID_HERE'
-- ORDER BY event_date ASC;
