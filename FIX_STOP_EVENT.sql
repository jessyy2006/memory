-- ============================================================================
-- FIX: Update stop_event to properly manage is_upcoming
-- ============================================================================
-- When an event is stopped:
-- 1. Set is_active = false for the stopped event
-- 2. Set is_upcoming = false for the stopped event
-- 3. Find the next upcoming event (earliest date >= today, not active)
-- 4. Set is_upcoming = true ONLY for that next event
-- Execute this in your Supabase SQL Editor
-- ============================================================================

CREATE OR REPLACE FUNCTION stop_event(p_event_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_rows_updated INT;
  v_next_upcoming_id UUID;
  v_next_upcoming_date DATE;
BEGIN
  -- Step 1: Deactivate the event AND clear is_upcoming
  UPDATE events
  SET is_active = false,
      is_upcoming = false,
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  IF v_rows_updated = 0 THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Event not found or already inactive'
    );
  ELSE
    -- Step 2: Clear is_upcoming for ALL events for this user
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = p_user_id;

    -- Step 3: Find the NEXT upcoming event
    -- Logic: Earliest event with date >= today that is not active
    -- If event has end_time, use it; otherwise use event_date
    SELECT id, event_date INTO v_next_upcoming_id, v_next_upcoming_date
    FROM events
    WHERE user_id = p_user_id
      AND is_active = false
      AND (
        -- If event has end_time, check if it hasn't passed
        (end_time IS NOT NULL AND
         (event_date || ' ' || end_time::TEXT)::TIMESTAMP >= NOW()) OR
        -- If no end_time, check if date is today or future
        (end_time IS NULL AND event_date >= CURRENT_DATE)
      )
    ORDER BY
      -- Sort by date first
      event_date ASC,
      -- Then by start_time if available
      COALESCE(start_time, '00:00:00'::TIME) ASC
    LIMIT 1;

    -- Step 4: Set is_upcoming = true for ONLY the next upcoming event
    IF v_next_upcoming_id IS NOT NULL THEN
      UPDATE events
      SET is_upcoming = true,
          updated_at = NOW()
      WHERE id = v_next_upcoming_id;

      RAISE NOTICE 'Set is_upcoming=true for event % (date: %)', v_next_upcoming_id, v_next_upcoming_date;
    END IF;

    v_result := json_build_object(
      'success', true,
      'event_id', p_event_id,
      'most_upcoming_event_id', v_next_upcoming_id,
      'most_upcoming_event_date', v_next_upcoming_date
    );
  END IF;

  RETURN v_result;
END;
$$;
