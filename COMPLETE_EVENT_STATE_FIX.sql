-- ============================================================================
-- COMPLETE EVENT STATE MANAGEMENT FIX
-- ============================================================================
-- This migration implements proper event state transitions with 3 boolean fields:
-- - is_active: Event is currently active (user clicked "Start Event")
-- - is_upcoming: Event is the next one to start (only ONE event can have this)
-- - is_ended: Event has been ended (user clicked "End Event")
--
-- Execute this in your Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- STEP 1: Add is_ended column to events table
-- ============================================================================

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS is_ended BOOLEAN DEFAULT false;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_events_is_ended ON events(is_ended);

COMMENT ON COLUMN events.is_ended IS 'True when event has been manually ended or date/time has passed';

-- ============================================================================
-- STEP 2: Fix existing data - Set correct is_ended and is_upcoming values
-- ============================================================================

DO $$
DECLARE
  v_user_id UUID;
  v_next_upcoming_id UUID;
BEGIN
  RAISE NOTICE 'Starting data migration...';

  -- Loop through all users with events
  FOR v_user_id IN
    SELECT DISTINCT user_id FROM events
  LOOP
    RAISE NOTICE 'Processing user: %', v_user_id;

    -- Step 1: Set is_ended = true for events that have passed or are inactive with old dates
    UPDATE events
    SET is_ended = true
    WHERE user_id = v_user_id
      AND is_active = false
      AND (
        -- Event date has passed (use <= so events at exact current time are considered ended)
        (end_time IS NOT NULL AND
         (event_date || ' ' || end_time::TEXT)::TIMESTAMP <= NOW()) OR
        (end_time IS NULL AND event_date < CURRENT_DATE)
      );

    -- Step 2: Clear is_upcoming for ALL events for this user
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = v_user_id;

    -- Step 3: Find the NEXT upcoming event
    -- Logic: Earliest event with is_ended = false and is_active = false
    SELECT id INTO v_next_upcoming_id
    FROM events
    WHERE user_id = v_user_id
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

    -- Step 4: Set is_upcoming = true for ONLY the next upcoming event
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

  RAISE NOTICE 'Data migration complete!';
END $$;

-- ============================================================================
-- STEP 3: Update start_event stored procedure
-- ============================================================================
-- When an event is started:
-- 1. Set is_active = true, is_upcoming = false, is_ended = false
-- 2. Only allow starting events with is_upcoming = true
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
  v_is_upcoming BOOLEAN;
  v_is_ended BOOLEAN;
BEGIN
  -- Check if requested event is marked as upcoming and not ended
  SELECT is_upcoming, is_ended INTO v_is_upcoming, v_is_ended
  FROM events
  WHERE id = p_event_id
    AND user_id = p_user_id;

  -- Validate event exists
  IF v_is_upcoming IS NULL THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Event not found'
    );
    RETURN v_result;
  END IF;

  -- Validate event is not ended
  IF v_is_ended = true THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Cannot start an ended event'
    );
    RETURN v_result;
  END IF;

  -- Get the event with is_upcoming = true for this user
  SELECT id, event_date INTO v_most_upcoming_id, v_event_date
  FROM events
  WHERE user_id = p_user_id
    AND is_upcoming = true
    AND is_ended = false
  LIMIT 1;

  -- Check if requested event is the upcoming one
  IF v_most_upcoming_id IS NULL THEN
    v_result := json_build_object(
      'success', false,
      'error', 'No upcoming events found'
    );
    RETURN v_result;
  END IF;

  IF v_most_upcoming_id != p_event_id THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Can only start the most upcoming event',
      'most_upcoming_event_id', v_most_upcoming_id,
      'most_upcoming_event_date', v_event_date
    );
    RETURN v_result;
  END IF;

  -- Deactivate all events for this user (ensures only one is active)
  UPDATE events
  SET is_active = false,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Start the event: is_active=true, is_upcoming=false, is_ended=false
  UPDATE events
  SET is_active = true,
      is_upcoming = false,
      is_ended = false,
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  RAISE NOTICE 'Started event % - is_active=true, is_upcoming=false, is_ended=false', p_event_id;

  v_result := json_build_object(
    'success', true,
    'event_id', p_event_id
  );

  RETURN v_result;
END;
$$;

-- ============================================================================
-- STEP 4: Update stop_event stored procedure
-- ============================================================================
-- When an event is stopped:
-- 1. Set is_active = false, is_upcoming = false, is_ended = true
-- 2. Find next upcoming event and set is_upcoming = true for it
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
  -- Step 1: End the event - is_active=false, is_upcoming=false, is_ended=true
  UPDATE events
  SET is_active = false,
      is_upcoming = false,
      is_ended = true,
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
    RAISE NOTICE 'Ended event % - is_active=false, is_upcoming=false, is_ended=true', p_event_id;

    -- Step 2: Clear is_upcoming for ALL events for this user
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = p_user_id;

    -- Step 3: Find the NEXT upcoming event
    -- Logic: Earliest event with is_ended = false and is_active = false
    SELECT id, event_date INTO v_next_upcoming_id, v_next_upcoming_date
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

    -- Step 4: Set is_upcoming = true for ONLY the next upcoming event
    IF v_next_upcoming_id IS NOT NULL THEN
      UPDATE events
      SET is_upcoming = true,
          updated_at = NOW()
      WHERE id = v_next_upcoming_id;

      RAISE NOTICE 'Set is_upcoming=true for next event % (date: %)', v_next_upcoming_id, v_next_upcoming_date;
    ELSE
      RAISE NOTICE 'No more upcoming events for user';
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

-- ============================================================================
-- STEP 5: Update get_events_sorted to return is_ended column
-- ============================================================================

-- Drop existing function first (required when changing return type)
DROP FUNCTION IF EXISTS get_events_sorted(uuid);

CREATE OR REPLACE FUNCTION get_events_sorted(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  name TEXT,
  event_date DATE,
  start_time TIME,
  end_time TIME,
  is_active BOOLEAN,
  is_upcoming BOOLEAN,
  is_ended BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.user_id,
    e.name,
    e.event_date,
    e.start_time,
    e.end_time,
    e.is_active,
    e.is_upcoming,
    e.is_ended,
    e.created_at,
    e.updated_at
  FROM events e
  WHERE e.user_id = p_user_id
  ORDER BY e.event_date ASC;
END;
$$;

-- ============================================================================
-- STEP 6: Verify the results
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
    ELSE ''
  END as status
FROM events
ORDER BY user_id, event_date ASC;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
-- Next steps:
-- 1. Update Swift EventRecord model to include isEnded: Bool field
-- 2. Update view filtering to use event.isEnded from database
-- 3. Test event state transitions: Start → End → Next event becomes upcoming
-- ============================================================================
