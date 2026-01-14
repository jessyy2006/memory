-- ============================================================================
-- FIX: Update start_event to use is_upcoming column properly
-- ============================================================================
-- The start_event function should check the is_upcoming column to determine
-- which event can be started, not just event_date.
-- Execute this in your Supabase SQL Editor
-- ============================================================================

CREATE OR REPLACE FUNCTION start_event(p_event_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_most_upcoming_id UUID;
  v_event_date DATE;
  v_result JSON;
  v_requested_event_upcoming BOOLEAN;
BEGIN
  -- Get the event with is_upcoming = true for this user
  SELECT id, event_date INTO v_most_upcoming_id, v_event_date
  FROM events
  WHERE user_id = p_user_id
    AND is_upcoming = true
  LIMIT 1;

  -- Check if requested event has is_upcoming = true
  SELECT is_upcoming INTO v_requested_event_upcoming
  FROM events
  WHERE id = p_event_id
    AND user_id = p_user_id;

  -- If no event is marked as upcoming, allow any future event to start
  IF v_most_upcoming_id IS NULL THEN
    -- Find the next upcoming event by date
    SELECT id, event_date INTO v_most_upcoming_id, v_event_date
    FROM events
    WHERE user_id = p_user_id
      AND is_active = false
      AND (
        (end_time IS NOT NULL AND
         (event_date || ' ' || end_time::TEXT)::TIMESTAMP >= NOW()) OR
        (end_time IS NULL AND event_date >= CURRENT_DATE)
      )
    ORDER BY
      event_date ASC,
      COALESCE(start_time, '00:00:00'::TIME) ASC
    LIMIT 1;

    -- If still no upcoming event found
    IF v_most_upcoming_id IS NULL THEN
      v_result := json_build_object(
        'success', false,
        'error', 'No upcoming events found'
      );
      RETURN v_result;
    END IF;

    -- If requested event is not the most upcoming by date
    IF v_most_upcoming_id != p_event_id THEN
      v_result := json_build_object(
        'success', false,
        'error', 'Can only start the most upcoming event',
        'most_upcoming_event_id', v_most_upcoming_id,
        'most_upcoming_event_date', v_event_date
      );
      RETURN v_result;
    END IF;
  ELSE
    -- Check if the requested event is the one marked as upcoming
    IF v_most_upcoming_id != p_event_id THEN
      v_result := json_build_object(
        'success', false,
        'error', 'Can only start the most upcoming event',
        'most_upcoming_event_id', v_most_upcoming_id,
        'most_upcoming_event_date', v_event_date
      );
      RETURN v_result;
    END IF;
  END IF;

  -- Deactivate all events for this user (ensures only one is active)
  UPDATE events
  SET is_active = false,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Activate the most upcoming event
  UPDATE events
  SET is_active = true,
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  v_result := json_build_object(
    'success', true,
    'event_id', p_event_id
  );

  RETURN v_result;
END;
$$;
