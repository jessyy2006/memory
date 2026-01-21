-- ============================================================================
-- FIX: End Event Button - Immediate isEnded = true
-- ============================================================================
-- Problem: When user clicks "End Event", the event stays on Events Home
-- Expected: Event should immediately have isEnded=true and move to Past Events
--
-- Root Cause:
-- - stop_event() sets is_ended=true explicitly
-- - Trigger fires and RECALCULATES is_ended based on time
-- - Since event hasn't naturally ended yet, trigger sets is_ended=false
-- - This overrides the manual stop!
--
-- Solution:
-- - Detect "manual stop" (is_active changes from true to false)
-- - If manual stop: Keep is_ended=true, don't recalculate
-- - If time/date change: Recalculate is_ended based on current time
-- ============================================================================

-- ============================================================================
-- STEP 1: Update stop_event() Function
-- ============================================================================
-- Force all flags when manually stopping an event

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
  v_event_name TEXT;
BEGIN
  -- Get event name for logging
  SELECT name INTO v_event_name FROM events WHERE id = p_event_id;

  RAISE NOTICE '';
  RAISE NOTICE '🛑 [stop_event] MANUALLY STOPPING EVENT: %', v_event_name;
  RAISE NOTICE '   Event ID: %', p_event_id;

  -- =========================================================================
  -- CRITICAL: Stop the event and mark as ended (manual termination)
  -- =========================================================================
  UPDATE events
  SET is_active = false,     -- No longer active
      is_ended = true,       -- FORCE ended (manual stop)
      is_future = false,     -- Not future (it's ended)
      is_upcoming = false,   -- Not upcoming (it's ended)
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  IF v_rows_updated = 0 THEN
    RAISE NOTICE '❌ [stop_event] Event not found or already inactive';
    v_result := json_build_object(
      'success', false,
      'error', 'Event not found or already inactive'
    );
  ELSE
    RAISE NOTICE '✅ [stop_event] Event stopped: is_active=false, is_ended=true, is_future=false, is_upcoming=false';

    -- Clear is_upcoming for ALL events for this user
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = p_user_id;

    -- Find the NEXT upcoming event with priority logic:
    -- PRIORITY 1: Events that are currently in their time window (start passed, end not passed)
    -- PRIORITY 2: Events that haven't started yet (earliest start time)
    -- PRIORITY 3: All-day events (no specific time)
    SELECT id, event_date INTO v_next_upcoming_id, v_next_upcoming_date
    FROM events
    WHERE user_id = p_user_id
      AND is_active = false
      AND is_ended = false    -- Exclude ended events
      AND is_future = true    -- ✅ ONLY events that are future can be upcoming
      AND (
        -- If event has end_time, check if it hasn't passed
        (end_time IS NOT NULL AND
         (event_date || ' ' || end_time::TEXT)::TIMESTAMP >= (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP) OR
        -- If no end_time, check if date is today or future
        (end_time IS NULL AND event_date >= CURRENT_DATE)
      )
    ORDER BY
      -- Priority 1: Events currently in their time window (start passed, end not passed)
      -- Priority 2: Events with specific times that haven't started
      -- Priority 3: All-day events
      CASE
        -- Events with times that have already started but not ended (IN PROGRESS)
        WHEN start_time IS NOT NULL AND end_time IS NOT NULL AND
             (event_date::TIMESTAMP + start_time) <= (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP AND
             (event_date::TIMESTAMP + end_time) > (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP
        THEN 1  -- HIGHEST PRIORITY: Currently in time window

        -- Events with specific times that haven't started yet
        WHEN start_time IS NOT NULL AND
             (event_date::TIMESTAMP + start_time) > (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP
        THEN 2  -- MEDIUM PRIORITY: Future timed events

        -- All-day events (no specific time)
        ELSE 3  -- LOWEST PRIORITY: All-day events
      END,
      event_date ASC,
      COALESCE(start_time, '23:59:59'::TIME) ASC  -- All-day events sort last
    LIMIT 1;

    -- Set is_upcoming = true for ONLY the next upcoming event (if it's future AND not ended)
    IF v_next_upcoming_id IS NOT NULL THEN
      UPDATE events
      SET is_upcoming = true,
          updated_at = NOW()
      WHERE id = v_next_upcoming_id
        AND is_future = true
        AND is_ended = false;  -- ✅ CRITICAL: Only set if not ended

      RAISE NOTICE '✅ [stop_event] Set is_upcoming=true for next event (ID: %)', v_next_upcoming_id;
    ELSE
      RAISE NOTICE '⚠️  [stop_event] No more upcoming events found';
    END IF;

    RAISE NOTICE '';

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
-- STEP 2: Update calculate_event_status() Trigger
-- ============================================================================
-- Add logic to detect manual stops and skip recalculation

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_pacific TIMESTAMP;
    event_start_datetime TIMESTAMP;
    event_end_datetime TIMESTAMP;
    time_based_is_ended BOOLEAN;
    is_manual_stop BOOLEAN;
BEGIN
    -- Get current time in Pacific timezone (PST/PDT)
    now_pacific := (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP;

    -- Calculate event start datetime
    IF NEW.start_time IS NOT NULL THEN
        event_start_datetime := NEW.event_date::TIMESTAMP + NEW.start_time;
    ELSE
        event_start_datetime := NEW.event_date::TIMESTAMP;
    END IF;

    -- Calculate event end datetime
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := NEW.event_date::TIMESTAMP + NEW.end_time;
    ELSE
        event_end_datetime := NEW.event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    -- =========================================================================
    -- STEP 1: Calculate what is_ended SHOULD be based on time
    -- =========================================================================
    time_based_is_ended := (now_pacific > event_end_datetime);

    -- =========================================================================
    -- STEP 2: Detect MANUAL STOP - is_ended being set to true when time says false
    -- =========================================================================
    IF TG_OP = 'UPDATE' THEN
        -- Manual stop if:
        -- 1. UPDATE is setting is_ended=true (NEW.is_ended = true)
        -- 2. Time-based calculation says should be false (time_based_is_ended = false)
        -- 3. This is a change from the old value (OLD.is_ended = false)
        is_manual_stop := (NEW.is_ended = true AND time_based_is_ended = false AND OLD.is_ended = false);
    ELSE
        is_manual_stop := false;
    END IF;

    -- =========================================================================
    -- STEP 3: If MANUAL STOP detected, preserve the manual values
    -- =========================================================================
    IF is_manual_stop THEN
        RAISE NOTICE '';
        RAISE NOTICE '🛑 [calculate_event_status] MANUAL STOP DETECTED for event %', COALESCE(NEW.id::TEXT, 'NEW');
        RAISE NOTICE '   Time says is_ended=% but UPDATE says is_ended=%', time_based_is_ended, NEW.is_ended;
        RAISE NOTICE '   Keeping explicit values: is_ended=%, is_future=%, is_upcoming=%',
            NEW.is_ended, NEW.is_future, NEW.is_upcoming;

        -- ✅ ENFORCE INVARIANT: Ended events cannot be upcoming or future
        NEW.is_upcoming := false;
        NEW.is_future := false;

        RAISE NOTICE '';
        RETURN NEW;  -- Don't recalculate, keep the manual values
    END IF;

    -- =========================================================================
    -- STEP 4: PRESERVE previously manually-ended events
    -- =========================================================================
    IF TG_OP = 'UPDATE' AND OLD.is_ended = true AND time_based_is_ended = false THEN
        -- Event was manually ended before - keep it ended
        RAISE NOTICE '';
        RAISE NOTICE '✅ [calculate_event_status] Preserving manually-ended event %', COALESCE(NEW.id::TEXT, 'NEW');
        NEW.is_ended := true;
        NEW.is_upcoming := false;
        NEW.is_future := false;
        RAISE NOTICE '';
        RETURN NEW;
    END IF;

    -- =========================================================================
    -- STEP 5: NORMAL RECALCULATION - Calculate based on time
    -- =========================================================================

    -- Set is_ended from time-based calculation
    NEW.is_ended := time_based_is_ended;

    -- Calculate is_future
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (now_pacific < event_end_datetime);

    -- Guard: Force is_upcoming=false if event has ended or is not future
    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF now_pacific < event_start_datetime OR now_pacific > event_end_datetime THEN
            NEW.is_active := false;
        END IF;
    END IF;

    -- Logging
    RAISE NOTICE 'Event % | Start: % | End: % | Now (Pacific): % | isActive: % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        event_start_datetime,
        event_end_datetime,
        now_pacific,
        NEW.is_active,
        NEW.is_future,
        NEW.is_ended,
        COALESCE(NEW.is_upcoming::TEXT, 'NULL');

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 3: Recreate Triggers
-- ============================================================================

-- Drop existing triggers
DROP TRIGGER IF EXISTS trigger_calculate_event_status_insert ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_update ON events;

-- Create BEFORE INSERT trigger
CREATE TRIGGER trigger_calculate_event_status_insert
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION calculate_event_status();

-- Create BEFORE UPDATE trigger
-- Include is_active, is_ended, and is_upcoming to allow recalculation
CREATE TRIGGER trigger_calculate_event_status_update
    BEFORE UPDATE ON events
    FOR EACH ROW
    WHEN (
        OLD.event_date IS DISTINCT FROM NEW.event_date OR
        OLD.start_time IS DISTINCT FROM NEW.start_time OR
        OLD.end_time IS DISTINCT FROM NEW.end_time OR
        OLD.is_active IS DISTINCT FROM NEW.is_active OR
        OLD.is_ended IS DISTINCT FROM NEW.is_ended OR
        OLD.is_upcoming IS DISTINCT FROM NEW.is_upcoming
    )
    EXECUTE FUNCTION calculate_event_status();

-- ============================================================================
-- STEP 4: Force Recalculation for ALL Existing Events
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 RECALCULATING ALL EVENTS...';
    RAISE NOTICE '';

    -- Touch event_date to trigger recalculation
    FOR event_rec IN SELECT id, name FROM events ORDER BY event_date ASC
    LOOP
        RAISE NOTICE 'Recalculating: %', event_rec.name;

        UPDATE events
        SET event_date = event_date
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Recalculation complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 5: Validation Query
-- ============================================================================

SELECT
    name,
    event_date,
    start_time,
    end_time,
    is_active,
    is_ended,
    is_future,
    is_upcoming,
    CASE
        WHEN is_active = true AND is_ended = false THEN '✅ ACTIVE'
        WHEN is_active = false AND is_ended = true THEN '✅ ENDED (Past Events)'
        WHEN is_active = false AND is_ended = false AND is_future = true THEN '✅ FUTURE (Events Home)'
        ELSE '❌ INVALID STATE'
    END as status_check,
    CASE
        WHEN end_time IS NOT NULL THEN
            EXTRACT(EPOCH FROM (
                (event_date::TIMESTAMP + end_time) -
                (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP
            )) / 3600
        ELSE NULL
    END as hours_until_end
FROM events
ORDER BY event_date DESC;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Fix Does:
-- 1. stop_event() explicitly sets is_ended=true when user clicks "End Event"
-- 2. Trigger calculates time-based is_ended FIRST
-- 3. Trigger detects manual stop: is_ended=true in UPDATE but time says false
-- 4. If manual stop: Preserve is_ended=true, set is_future=false, is_upcoming=false
-- 5. If previously manually ended: Preserve ended state on subsequent updates
-- 6. Otherwise: Use time-based calculation
-- 7. Result: Manual stops work for ALL events (active or inactive)
--
-- Expected Behavior:
-- ✅ Click "End Event" (on ANY event):
--    - Event immediately gets is_ended=true, is_active=false
--    - Event moves to Past Events screen
--    - Next upcoming event gets is_upcoming=true
--
-- ✅ Time-based automatic ending:
--    - When event's end time passes, is_ended automatically becomes true
--    - Event automatically moves to Past Events
--
-- ✅ Manual stop detection works for:
--    - Active events (is_active=true)
--    - Inactive future events (is_active=false, is_future=true)
--    - Any event that hasn't naturally ended yet
-- ============================================================================
