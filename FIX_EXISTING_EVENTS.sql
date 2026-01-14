-- ============================================================================
-- FIX: Correct is_upcoming for all existing events
-- ============================================================================
-- This script fixes the is_upcoming flag for all events in the database.
-- It ensures only ONE event per user has is_upcoming = true (the next one).
-- Execute this in your Supabase SQL Editor AFTER running FIX_STOP_EVENT.sql
-- ============================================================================

DO $$
DECLARE
  v_user_id UUID;
  v_next_upcoming_id UUID;
BEGIN
  -- Loop through all users with events
  FOR v_user_id IN
    SELECT DISTINCT user_id FROM events
  LOOP
    RAISE NOTICE 'Processing user: %', v_user_id;

    -- Clear is_upcoming for ALL events for this user
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = v_user_id;

    -- Find the NEXT upcoming event for this user
    -- Logic: Earliest event with date >= today that is not active
    SELECT id INTO v_next_upcoming_id
    FROM events
    WHERE user_id = v_user_id
      AND is_active = false
      AND (
        -- If event has end_time, check if it hasn't passed
        (end_time IS NOT NULL AND
         (event_date || ' ' || end_time::TEXT)::TIMESTAMP >= NOW()) OR
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

      RAISE NOTICE '  → Set is_upcoming=true for event %', v_next_upcoming_id;
    ELSE
      RAISE NOTICE '  → No upcoming events found for this user';
    END IF;
  END LOOP;

  RAISE NOTICE 'Migration complete!';
END $$;

-- Verify the results
SELECT
  user_id,
  id,
  name,
  event_date,
  is_active,
  is_upcoming,
  CASE
    WHEN is_upcoming THEN '← MOST UPCOMING'
    WHEN is_active THEN '← ACTIVE'
    ELSE ''
  END as status
FROM events
ORDER BY user_id, event_date ASC;
