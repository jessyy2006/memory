-- ============================================================================
-- FIX FUTURE EVENTS BEING MARKED AS "ENDED"
-- ============================================================================
-- This migration fixes the bug where future events are incorrectly marked as
-- "ended" in the database, causing them to show as "Ended" instead of "Upcoming"
-- in the UI.
--
-- Root cause: The COMPLETE_EVENT_STATE_FIX.sql migration runs ONCE on existing
-- data and may incorrectly mark future events as ended. We need triggers to
-- ensure is_ended is calculated correctly on INSERT/UPDATE.
--
-- Execute this in your Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- STEP 1: Create function to auto-calculate is_ended based on date/time
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_calculate_is_ended()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_event_end_datetime TIMESTAMP;
BEGIN
  -- Calculate if event has ended based on date + end_time
  IF NEW.end_time IS NOT NULL THEN
    -- Combine event_date + end_time to create full datetime
    v_event_end_datetime := (NEW.event_date || ' ' || NEW.end_time::TEXT)::TIMESTAMP;

    -- Event is ended if end datetime has passed (use < not <=)
    IF v_event_end_datetime < NOW() THEN
      NEW.is_ended := true;
    ELSE
      NEW.is_ended := false;
    END IF;
  ELSE
    -- No end_time - use date-only comparison
    IF NEW.event_date < CURRENT_DATE THEN
      NEW.is_ended := true;
    ELSE
      NEW.is_ended := false;
    END IF;
  END IF;

  -- IMPORTANT: If event is being manually set to is_ended=true via stop_event,
  -- don't override it. This trigger only auto-calculates is_ended when it's
  -- not being explicitly set.
  -- We detect "explicit set" by checking if is_active is being set to false
  -- AND is_ended is being set to true simultaneously (which is what stop_event does)
  IF TG_OP = 'UPDATE' THEN
    -- If both is_active and is_ended are being explicitly set (stop_event case)
    -- Don't override - let the explicit value stand
    IF OLD.is_active = true AND NEW.is_active = false AND NEW.is_ended = true THEN
      -- This is stop_event - don't override
      RETURN NEW;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: Create BEFORE INSERT trigger to auto-calculate is_ended
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_before_insert_auto_calculate_is_ended ON events;

CREATE TRIGGER trigger_before_insert_auto_calculate_is_ended
  BEFORE INSERT ON events
  FOR EACH ROW
  EXECUTE FUNCTION auto_calculate_is_ended();

-- ============================================================================
-- STEP 3: Create BEFORE UPDATE trigger to auto-calculate is_ended
-- ============================================================================
-- This ensures is_ended stays correct even if event date/time is updated

DROP TRIGGER IF EXISTS trigger_before_update_auto_calculate_is_ended ON events;

CREATE TRIGGER trigger_before_update_auto_calculate_is_ended
  BEFORE UPDATE ON events
  FOR EACH ROW
  WHEN (
    -- Only recalculate if date or time fields changed
    OLD.event_date IS DISTINCT FROM NEW.event_date OR
    OLD.start_time IS DISTINCT FROM NEW.start_time OR
    OLD.end_time IS DISTINCT FROM NEW.end_time
  )
  EXECUTE FUNCTION auto_calculate_is_ended();

-- ============================================================================
-- STEP 4: Fix existing data - Recalculate is_ended for ALL events
-- ============================================================================

DO $$
DECLARE
  v_event RECORD;
  v_event_end_datetime TIMESTAMP;
  v_new_is_ended BOOLEAN;
BEGIN
  RAISE NOTICE 'Recalculating is_ended for all events...';

  FOR v_event IN SELECT * FROM events WHERE is_active = false
  LOOP
    -- Calculate correct is_ended value
    IF v_event.end_time IS NOT NULL THEN
      v_event_end_datetime := (v_event.event_date || ' ' || v_event.end_time::TEXT)::TIMESTAMP;
      v_new_is_ended := v_event_end_datetime < NOW();
    ELSE
      v_new_is_ended := v_event.event_date < CURRENT_DATE;
    END IF;

    -- Only update if value is wrong
    IF v_event.is_ended != v_new_is_ended THEN
      UPDATE events
      SET is_ended = v_new_is_ended,
          updated_at = NOW()
      WHERE id = v_event.id;

      RAISE NOTICE 'Fixed event % ("%"): is_ended %→%',
        v_event.id, v_event.name, v_event.is_ended, v_new_is_ended;
    END IF;
  END LOOP;

  RAISE NOTICE 'Recalculation complete!';
END $$;

-- ============================================================================
-- STEP 5: Recalculate is_upcoming for all users (trigger from FIX_EVENT_CREATION_STATE.sql)
-- ============================================================================

DO $$
DECLARE
  v_user_id UUID;
BEGIN
  RAISE NOTICE 'Recalculating is_upcoming for all users...';

  FOR v_user_id IN
    SELECT DISTINCT user_id FROM events
  LOOP
    -- Call the recalculate function from FIX_EVENT_CREATION_STATE.sql
    -- This ensures is_upcoming is set correctly after fixing is_ended
    PERFORM recalculate_upcoming_event(v_user_id);
  END LOOP;

  RAISE NOTICE 'is_upcoming recalculation complete!';
END $$;

-- ============================================================================
-- STEP 6: Verify the results
-- ============================================================================

SELECT
  id,
  name,
  event_date,
  start_time,
  end_time,
  is_active,
  is_upcoming,
  is_ended,
  CASE
    WHEN is_active THEN '✅ ACTIVE'
    WHEN is_upcoming THEN '🔵 UPCOMING'
    WHEN is_ended THEN '⚪ ENDED'
    ELSE '⏸️ WAITING'
  END as status,
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
-- 1. Creates triggers to auto-calculate is_ended on INSERT/UPDATE
-- 2. Fixes existing events that were incorrectly marked as ended
-- 3. Recalculates is_upcoming for all users
-- 4. Future events will now correctly show as "Upcoming" not "Ended"
--
-- Expected behavior after this migration:
-- - New events: is_ended auto-calculated based on date/time
-- - Future events: is_ended = false, is_upcoming = true (if closest)
-- - Past events: is_ended = true
-- - Active events: is_active = true, is_ended = false
-- ============================================================================
