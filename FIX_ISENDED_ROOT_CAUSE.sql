-- ============================================================================
-- FIX: isEnded Root Cause - Timezone Aware Time Comparison
-- ============================================================================
-- ROOT CAUSE IDENTIFIED:
-- - LOCALTIMESTAMP returns the DATABASE SERVER's local time (UTC for Supabase)
-- - User creates event at 3 PM PST, stored as 15:00:00
-- - Server time is 8 PM UTC (12 PM PST = 20:00 UTC)
-- - Comparison: 20:00 > 15:00 = TRUE (WRONG!)
--
-- THE REAL PROBLEM:
-- We're comparing UTC server time against local PST times stored in TIME fields.
-- TIME fields have NO timezone information!
--
-- SOLUTION:
-- Use timezone-aware timestamps. Convert (event_date + time) to TIMESTAMPTZ
-- using the user's timezone, then compare with NOW() (which is always UTC).
--
-- However, we don't store user timezone in the database...
-- BETTER SOLUTION:
-- Use CURRENT_DATE and CURRENT_TIME which respect the session timezone,
-- OR accept that all times are stored/compared in UTC.
--
-- SIMPLEST FIX:
-- Assume all times are in UTC. Users must enter times in UTC, or we need
-- client-side timezone conversion.
--
-- WAIT - Let's think differently:
-- The app is storing local times (PST) in the TIME field.
-- The trigger needs to interpret these as local times in the SAME timezone.
--
-- PostgreSQL stores TIME without timezone info.
-- When we do: event_date::TIMESTAMP + end_time
-- This creates a TIMESTAMP (no timezone) combining the date and time.
--
-- The issue: LOCALTIMESTAMP on Supabase returns UTC time (server timezone).
-- We need to compare in the SAME timezone.
--
-- FIX: Use CURRENT_TIMESTAMP AT TIME ZONE 'America/Los_Angeles'
-- Or better: Store everything in UTC and convert on the client side.
--
-- BEST FIX FOR THIS APP:
-- Since we can't know the user's timezone from the database alone,
-- we should:
-- 1. Store times in UTC in the database
-- 2. Convert to/from user's local timezone in the Swift app
--
-- BUT - The app is already storing local times!
-- So we need a different approach...
--
-- ACTUAL FIX:
-- Use NOW() AT TIME ZONE 'America/Los_Angeles' to get Pacific time
-- OR better: Accept a timezone parameter from the client
-- OR best: Fix at the Swift level to store UTC times
--
-- FOR NOW - Quick Fix:
-- Use Pacific timezone for comparisons (hardcoded for this user)
-- ============================================================================

-- ============================================================================
-- OPTION 1: Hardcode Pacific Timezone (Quick Fix)
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_pacific TIMESTAMP;  -- Current time in Pacific timezone
    event_start_datetime TIMESTAMP;  -- Local timestamp
    event_end_datetime TIMESTAMP;  -- Local timestamp
BEGIN
    -- Get current time in Pacific timezone (PST/PDT)
    -- This matches how the user is entering times in the app
    now_pacific := (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP;

    -- Calculate event start datetime (interpreted as Pacific time)
    IF NEW.start_time IS NOT NULL THEN
        event_start_datetime := NEW.event_date::TIMESTAMP + NEW.start_time;
    ELSE
        -- No start time - use beginning of event day
        event_start_datetime := NEW.event_date::TIMESTAMP;
    END IF;

    -- Calculate event end datetime (interpreted as Pacific time)
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := NEW.event_date::TIMESTAMP + NEW.end_time;
    ELSE
        -- No end time - use end of event day (23:59:59)
        event_end_datetime := NEW.event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    -- =========================================================================
    -- CRITICAL LOGIC: Compare Pacific time to Pacific time
    -- =========================================================================
    NEW.is_ended := (now_pacific > event_end_datetime);

    -- is_future = true if:
    --   1. NOT ended (is_ended = false)
    --   2. NOT active (is_active = false)
    --   3. End time is still in the future
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (now_pacific < event_end_datetime);

    -- =========================================================================
    -- Guard Clause: Force is_upcoming=false if event has ended or is not future
    -- =========================================================================
    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF now_pacific < event_start_datetime OR now_pacific > event_end_datetime THEN
            NEW.is_active := false;
        END IF;
    END IF;

    -- =========================================================================
    -- Logging: Print status for every event processed (PACIFIC TIME)
    -- =========================================================================
    RAISE NOTICE 'Event % | Start: % | End: % | Now (Pacific): % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        event_start_datetime,
        event_end_datetime,
        now_pacific,
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
    RAISE NOTICE '🔄 RECALCULATING ALL EVENTS WITH PACIFIC TIMEZONE...';
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
-- STEP 4: Validation - Show all events with PACIFIC time comparisons
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
    END as computed_end_datetime_pacific,
    (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP as current_time_pacific,
    CASE
        WHEN end_time IS NOT NULL THEN
            (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP < (event_date::TIMESTAMP + end_time)
        ELSE
            (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP < (event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second')
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
-- STEP 5: Test Cases Verification (PACIFIC TIME)
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    now_pacific TIMESTAMP;
BEGIN
    now_pacific := (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP;

    RAISE NOTICE '';
    RAISE NOTICE '🔍 TEST CASES VERIFICATION (current PACIFIC time: %)', now_pacific;
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
            END as end_datetime_pacific
        FROM events
        WHERE event_date = CURRENT_DATE  -- Only today's events
        ORDER BY COALESCE(start_time, '00:00:00'::TIME) ASC
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '📅 Event: %', event_rec.name;
        RAISE NOTICE '   Time Range: % - %',
            COALESCE(event_rec.start_time::TEXT, 'no start'),
            COALESCE(event_rec.end_time::TEXT, 'no end');
        RAISE NOTICE '   End Datetime (PACIFIC): %', event_rec.end_datetime_pacific;
        RAISE NOTICE '   Current Time (PACIFIC): %', now_pacific;
        RAISE NOTICE '   Time Comparison: current < end? %', (now_pacific < event_rec.end_datetime_pacific);
        RAISE NOTICE '   Database Values: is_ended=%, is_future=%',
            event_rec.is_ended, event_rec.is_future;

        -- Validate logic
        IF now_pacific < event_rec.end_datetime_pacific THEN
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
-- DEBUG: Show timezone information
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🌐 TIMEZONE DEBUG INFO:';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Database timezone: %', CURRENT_SETTING('timezone');
    RAISE NOTICE 'NOW() (UTC): %', NOW();
    RAISE NOTICE 'LOCALTIMESTAMP (server local): %', LOCALTIMESTAMP;
    RAISE NOTICE 'NOW() AT TIME ZONE ''America/Los_Angeles'': %', (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP;
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Migration Does:
-- 1. Fixes the root cause: LOCALTIMESTAMP was returning UTC (server time)
-- 2. Uses NOW() AT TIME ZONE 'America/Los_Angeles' to get Pacific time
-- 3. Compares Pacific times consistently (now_pacific vs event times stored in Pacific)
-- 4. Forces recalculation of all existing events
-- 5. Provides detailed validation with PACIFIC time
--
-- Expected Results (using PACIFIC time):
-- ✅ Event today 5 PM - 7 PM (current 12 PM PST): is_ended=false, is_future=true
-- ✅ Event today 11 AM - 3 PM (current 12 PM PST): is_ended=false, is_future=true
-- ✅ Event today 9 AM - 11 AM (current 12 PM PST): is_ended=true, is_future=false
-- ✅ Events without specific times work correctly (unchanged)
-- ✅ Events on future dates work correctly (unchanged)
--
-- Key Changes:
-- - Changed: LOCALTIMESTAMP → (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP
-- - Reason: LOCALTIMESTAMP returns server timezone (UTC), not user timezone (Pacific)
-- - Logic: currentTime (Pacific) < event.endTime (Pacific)
--
-- IMPORTANT NOTE:
-- This fix hardcodes Pacific timezone. For multi-timezone support, you would need to:
-- 1. Store user's timezone in the database
-- 2. Pass timezone as a parameter to the trigger
-- 3. Or store all times in UTC and convert client-side (recommended)
-- ============================================================================
