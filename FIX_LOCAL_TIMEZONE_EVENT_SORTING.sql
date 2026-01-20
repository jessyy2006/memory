-- ============================================================================
-- FIX: Local Timezone Event Sorting (Corrected)
-- ============================================================================
-- Previous Bug: AT TIME ZONE 'UTC' incorrectly interpreted local times as UTC
--
-- Example of Previous Bug:
-- - User creates event 3 PM PST (UTC-8)
-- - Stored as: event_date=2026-01-20, end_time=15:00:00
-- - Old code: (date + time) AT TIME ZONE 'UTC' = 2026-01-20 15:00:00 UTC ❌
-- - Should be: 2026-01-20 15:00:00 PST = 2026-01-20 23:00:00 UTC ✅
-- - Current time: 12 PM PST = 20:00 UTC
-- - Wrong: 20:00 > 15:00 = TRUE (event marked as ended!) ❌
-- - Correct: 20:00 > 23:00 = FALSE (event still ongoing!) ✅
--
-- Solution: Remove AT TIME ZONE conversion and use local timestamps consistently
-- ============================================================================

-- ============================================================================
-- STEP 1: Rewrite calculate_event_status() WITHOUT timezone conversion
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_local TIMESTAMP;  -- Local timestamp (no timezone)
    event_start_datetime TIMESTAMP;  -- Local timestamp
    event_end_datetime TIMESTAMP;  -- Local timestamp
BEGIN
    -- Use local time (no timezone conversion)
    now_local := LOCALTIMESTAMP;

    -- Calculate event start datetime (local time)
    IF NEW.start_time IS NOT NULL THEN
        event_start_datetime := NEW.event_date::TIMESTAMP + NEW.start_time;
    ELSE
        -- No start time - use beginning of event day
        event_start_datetime := NEW.event_date::TIMESTAMP;
    END IF;

    -- Calculate event end datetime (local time)
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := NEW.event_date::TIMESTAMP + NEW.end_time;
    ELSE
        -- No end time - use end of event day (23:59:59)
        event_end_datetime := NEW.event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    -- =========================================================================
    -- CRITICAL LOGIC: Local currentTime < local event.endTime
    -- =========================================================================
    -- New Required Logic:
    -- An event is "Upcoming/Active" (isFuture = true) if:
    -- 1. eventDate is in the future (strictly > today), OR
    -- 2. eventDate is today AND currentTime < event.endTime
    --
    -- is_ended = true ONLY when: now_local > event_end_datetime

    NEW.is_ended := (now_local > event_end_datetime);

    -- is_future = true if:
    --   1. NOT ended (is_ended = false)
    --   2. NOT active (is_active = false)
    --   3. End time is still in the future (now_local < event_end_datetime)
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (now_local < event_end_datetime);

    -- =========================================================================
    -- Guard Clause: Force is_upcoming=false if event has ended or is not future
    -- =========================================================================
    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF now_local < event_start_datetime OR now_local > event_end_datetime THEN
            NEW.is_active := false;
        END IF;
    END IF;

    -- =========================================================================
    -- Logging: Print status for every event processed (LOCAL TIME)
    -- =========================================================================
    RAISE NOTICE 'Event % | Start: % | End: % | Now: % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        event_start_datetime,
        event_end_datetime,
        now_local,
        NEW.is_future,
        NEW.is_ended,
        COALESCE(NEW.is_upcoming::TEXT, 'NULL');

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: Recreate triggers
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
CREATE TRIGGER trigger_calculate_event_status_update
    BEFORE UPDATE ON events
    FOR EACH ROW
    WHEN (
        OLD.event_date IS DISTINCT FROM NEW.event_date OR
        OLD.start_time IS DISTINCT FROM NEW.start_time OR
        OLD.end_time IS DISTINCT FROM NEW.end_time OR
        OLD.is_active IS DISTINCT FROM NEW.is_active OR
        OLD.is_ended IS DISTINCT FROM NEW.is_ended
    )
    EXECUTE FUNCTION calculate_event_status();

-- ============================================================================
-- STEP 3: Force recalculation for ALL existing events
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 RECALCULATING ALL EVENTS WITH LOCAL TIMEZONE LOGIC...';
    RAISE NOTICE '';

    -- Touch event_date to trigger the BEFORE UPDATE trigger
    FOR event_rec IN SELECT id, name FROM events ORDER BY event_date ASC
    LOOP
        RAISE NOTICE 'Recalculating: %', event_rec.name;

        UPDATE events
        SET event_date = event_date  -- This triggers calculate_event_status()
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Recalculation complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 4: Validation - Show all events with LOCAL time comparisons
-- ============================================================================

SELECT
    name,
    event_date,
    start_time,
    end_time,
    CASE
        WHEN end_time IS NOT NULL THEN
            event_date::TIMESTAMP + end_time
        ELSE
            event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second'
    END as computed_end_datetime_local,
    LOCALTIMESTAMP as current_time_local,
    CASE
        WHEN end_time IS NOT NULL THEN
            LOCALTIMESTAMP < (event_date::TIMESTAMP + end_time)
        ELSE
            LOCALTIMESTAMP < (event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second')
    END as should_be_future,
    is_ended,
    is_future,
    is_active,
    is_upcoming,
    CASE
        WHEN is_future AND NOT is_ended THEN '✅ ON EVENTS HOME (correct)'
        WHEN is_ended AND NOT is_future THEN '✅ ON PAST EVENTS (correct)'
        WHEN is_future AND is_ended THEN '❌ LOGIC ERROR'
        WHEN NOT is_future AND NOT is_ended THEN '⚠️  CHECK MANUALLY'
        ELSE '⏸️  OTHER'
    END as validation_status
FROM events
ORDER BY event_date ASC, COALESCE(start_time, '00:00:00'::TIME) ASC;

-- ============================================================================
-- STEP 5: Test Cases Verification (LOCAL TIME)
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    now_local TIMESTAMP;
BEGIN
    now_local := LOCALTIMESTAMP;

    RAISE NOTICE '';
    RAISE NOTICE '🔍 TEST CASES VERIFICATION (current LOCAL time: %)', now_local;
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR event_rec IN
        SELECT
            name,
            event_date,
            start_time,
            end_time,
            is_ended,
            is_future,
            CASE
                WHEN end_time IS NOT NULL THEN
                    event_date::TIMESTAMP + end_time
                ELSE
                    event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second'
            END as end_datetime_local
        FROM events
        WHERE event_date = CURRENT_DATE  -- Only today's events
        ORDER BY COALESCE(start_time, '00:00:00'::TIME) ASC
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '📅 Event: %', event_rec.name;
        RAISE NOTICE '   Time Range: % - %',
            COALESCE(event_rec.start_time::TEXT, 'no start'),
            COALESCE(event_rec.end_time::TEXT, 'no end');
        RAISE NOTICE '   End Datetime (LOCAL): %', event_rec.end_datetime_local;
        RAISE NOTICE '   Current Time (LOCAL): %', now_local;
        RAISE NOTICE '   Time Comparison: current < end? %', (now_local < event_rec.end_datetime_local);
        RAISE NOTICE '   Database Values: is_ended=%, is_future=%',
            event_rec.is_ended, event_rec.is_future;

        -- Validate logic
        IF now_local < event_rec.end_datetime_local THEN
            -- Event end time is in the future - should NOT be ended
            IF event_rec.is_ended THEN
                RAISE NOTICE '   ❌ BUG: Event end is in future but is_ended=true';
            ELSE
                RAISE NOTICE '   ✅ CORRECT: Event has not ended yet';
            END IF;

            IF NOT event_rec.is_future THEN
                RAISE NOTICE '   ❌ BUG: Event should be is_future=true';
            ELSE
                RAISE NOTICE '   ✅ CORRECT: Event is marked as future';
            END IF;
        ELSE
            -- Event end time has passed - should be ended
            IF NOT event_rec.is_ended THEN
                RAISE NOTICE '   ❌ BUG: Event end time passed but is_ended=false';
            ELSE
                RAISE NOTICE '   ✅ CORRECT: Event is marked as ended';
            END IF;
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Migration Does:
-- 1. Removes incorrect AT TIME ZONE 'UTC' conversion
-- 2. Uses LOCALTIMESTAMP for all comparisons (user's local timezone)
-- 3. Ensures event times are interpreted in the same timezone they were created
-- 4. Forces recalculation of all existing events
-- 5. Provides detailed validation with LOCAL time
--
-- Expected Results (using LOCAL time):
-- ✅ Event today 5 PM - 7 PM (current 12 PM): is_ended=false, is_future=true
-- ✅ Event today 11 AM - 3 PM (current 12 PM): is_ended=false, is_future=true
-- ✅ Event today 9 AM - 11 AM (current 12 PM): is_ended=true, is_future=false
-- ✅ Events without specific times work correctly (unchanged)
-- ✅ Events on future dates work correctly (unchanged)
--
-- Key Changes:
-- - Removed: AT TIME ZONE 'UTC' (was misinterpreting local time as UTC)
-- - Added: LOCALTIMESTAMP (consistent local time comparison)
-- - Logic: currentTime < event.endTime (both in LOCAL timezone)
-- ============================================================================
