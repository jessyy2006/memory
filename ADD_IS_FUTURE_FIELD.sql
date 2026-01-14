-- ============================================================================
-- ADD IS_FUTURE FIELD TO EVENTS
-- ============================================================================
-- This migration adds a new "is_future" boolean field to support displaying
-- multiple future events with the "Upcoming" badge, while maintaining
-- is_upcoming for the single soonest event.
--
-- Logic Requirements:
-- - is_upcoming: true ONLY for the single soonest event
-- - is_future: true for ANY event that has not started and has not ended
-- - Relationship: If is_upcoming = true, then is_future must also be true
-- - Exclusion: If event is future but not soonest, is_upcoming = false, is_future = true
--
-- Execute this in your Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- STEP 1: Add is_future column to events table
-- ============================================================================

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS is_future BOOLEAN DEFAULT false;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_events_is_future ON events(is_future);

COMMENT ON COLUMN events.is_future IS 'True when event is in the future (not started and not ended)';

-- ============================================================================
-- STEP 2: Create function to auto-calculate is_future
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_calculate_is_future()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_event_end_datetime TIMESTAMP;
  v_has_ended BOOLEAN;
BEGIN
  -- Calculate if event has ended based on date + end_time
  IF NEW.end_time IS NOT NULL THEN
    -- Combine event_date + end_time to create full datetime
    v_event_end_datetime := (NEW.event_date || ' ' || NEW.end_time::TEXT)::TIMESTAMP;
    -- Event has ended if end datetime has passed
    v_has_ended := v_event_end_datetime < NOW();
  ELSE
    -- No end_time - use date-only comparison
    v_has_ended := NEW.event_date < CURRENT_DATE;
  END IF;

  -- is_future is true if:
  -- 1. Event has NOT ended (v_has_ended = false), AND
  -- 2. Event is NOT currently active (is_active = false)
  NEW.is_future := (NOT v_has_ended) AND (NEW.is_active = false);

  -- Constraint: If is_upcoming = true, then is_future must also be true
  IF NEW.is_upcoming = true AND NEW.is_future = false THEN
    -- This should never happen, but enforce the constraint
    RAISE NOTICE 'Constraint violation detected: is_upcoming=true but is_future=false for event %', NEW.id;
    NEW.is_future := true;
  END IF;

  -- Constraint: If is_ended = true, then is_future must be false
  IF NEW.is_ended = true THEN
    NEW.is_future := false;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 3: Create BEFORE INSERT trigger
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_before_insert_auto_calculate_is_future ON events;

CREATE TRIGGER trigger_before_insert_auto_calculate_is_future
  BEFORE INSERT ON events
  FOR EACH ROW
  EXECUTE FUNCTION auto_calculate_is_future();

-- ============================================================================
-- STEP 4: Create BEFORE UPDATE trigger
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_before_update_auto_calculate_is_future ON events;

CREATE TRIGGER trigger_before_update_auto_calculate_is_future
  BEFORE UPDATE ON events
  FOR EACH ROW
  WHEN (
    -- Recalculate if any relevant fields changed
    OLD.event_date IS DISTINCT FROM NEW.event_date OR
    OLD.start_time IS DISTINCT FROM NEW.start_time OR
    OLD.end_time IS DISTINCT FROM NEW.end_time OR
    OLD.is_active IS DISTINCT FROM NEW.is_active OR
    OLD.is_ended IS DISTINCT FROM NEW.is_ended OR
    OLD.is_upcoming IS DISTINCT FROM NEW.is_upcoming
  )
  EXECUTE FUNCTION auto_calculate_is_future();

-- ============================================================================
-- STEP 5: Update start_event to set is_future = false
-- ============================================================================
-- When starting an event, set is_future to false (event is now active)

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

  -- Start the event: is_active=true, is_upcoming=false, is_ended=false, is_future=false
  UPDATE events
  SET is_active = true,
      is_upcoming = false,
      is_ended = false,
      is_future = false,
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  RAISE NOTICE 'Started event % - is_active=true, is_upcoming=false, is_ended=false, is_future=false', p_event_id;

  v_result := json_build_object(
    'success', true,
    'event_id', p_event_id
  );

  RETURN v_result;
END;
$$;

-- ============================================================================
-- STEP 6: Update get_events_sorted to return is_future
-- ============================================================================

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
  is_future BOOLEAN,
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
    e.is_future,
    e.is_ended,
    e.created_at,
    e.updated_at
  FROM events e
  WHERE e.user_id = p_user_id
  ORDER BY e.event_date ASC;
END;
$$;

-- ============================================================================
-- STEP 7: Data migration - Set is_future for ALL existing events
-- ============================================================================

DO $$
DECLARE
  v_event RECORD;
  v_event_end_datetime TIMESTAMP;
  v_has_ended BOOLEAN;
  v_new_is_future BOOLEAN;
BEGIN
  RAISE NOTICE 'Calculating is_future for all events...';

  FOR v_event IN SELECT * FROM events
  LOOP
    -- Calculate if event has ended
    IF v_event.end_time IS NOT NULL THEN
      v_event_end_datetime := (v_event.event_date || ' ' || v_event.end_time::TEXT)::TIMESTAMP;
      v_has_ended := v_event_end_datetime < NOW();
    ELSE
      v_has_ended := v_event.event_date < CURRENT_DATE;
    END IF;

    -- Calculate is_future
    v_new_is_future := (NOT v_has_ended) AND (v_event.is_active = false);

    -- Update event
    UPDATE events
    SET is_future = v_new_is_future,
        updated_at = NOW()
    WHERE id = v_event.id;

    RAISE NOTICE 'Event % ("%"): is_future=%', v_event.id, v_event.name, v_new_is_future;
  END LOOP;

  RAISE NOTICE 'is_future calculation complete!';
END $$;

-- ============================================================================
-- STEP 8: Verify the results
-- ============================================================================

SELECT
  id,
  name,
  event_date,
  is_active,
  is_upcoming,
  is_future,
  is_ended,
  CASE
    WHEN is_active THEN '✅ ACTIVE'
    WHEN is_upcoming THEN '🔵 MOST UPCOMING (can start)'
    WHEN is_future THEN '🔵 FUTURE (upcoming badge, cannot start yet)'
    WHEN is_ended THEN '⚪ ENDED'
    ELSE '⏸️ UNKNOWN STATE'
  END as ui_status,
  CASE
    WHEN end_time IS NOT NULL THEN
      (event_date || ' ' || end_time::TEXT)::TIMESTAMP
    ELSE
      event_date::TIMESTAMP
  END as computed_end_time,
  NOW() as current_time
FROM events
ORDER BY event_date ASC;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
-- What this migration does:
-- 1. Adds is_future BOOLEAN column to events table
-- 2. Creates triggers to auto-calculate is_future on INSERT/UPDATE
-- 3. Updates start_event to set is_future = false when activating
-- 4. Updates get_events_sorted to return is_future
-- 5. Sets is_future correctly for all existing events
--
-- Expected behavior after this migration:
-- - Soonest future event: is_upcoming = true, is_future = true (blue badge, can start)
-- - Other future events: is_upcoming = false, is_future = true (blue badge, can't start)
-- - Active event: is_active = true, is_future = false (green badge)
-- - Ended events: is_ended = true, is_future = false (gray badge)
-- ============================================================================
